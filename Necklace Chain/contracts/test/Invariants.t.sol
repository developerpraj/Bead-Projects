// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FactionToken} from "../src/FactionToken.sol";
import {BeadToken} from "../src/BeadToken.sol";
import {EkecheiriaPool} from "../src/EkecheiriaPool.sol";
import {CosmicNecklace} from "../src/CosmicNecklace.sol";
import {Faction, MatchStatus, Outcome} from "../src/interfaces/PoolTypes.sol";
import {NecklaceBase} from "./NecklaceBase.sol";

/// @dev Drives the pool through random but legal-looking sequences; failed calls are swallowed so the invariants see only real state.
contract PoolHandler is Test {
    EkecheiriaPool internal pool;
    BeadToken internal bead;
    CosmicNecklace internal necklace;
    FactionToken internal homeToken;
    FactionToken internal awayToken;
    uint256 internal matchId;
    uint256 internal kickoff;
    address[] internal actors;
    address internal oracle;

    uint256 public forges;
    uint256 public settlementClaims;
    uint256 public refundClaims;
    uint256 public earlyWithdrawals;

    constructor(NecklaceBase t, address[] memory actors_, address oracle_) {
        pool = t.pool();
        bead = t.bead();
        necklace = t.necklace();
        homeToken = FactionToken(t.homeToken());
        awayToken = FactionToken(t.awayToken());
        matchId = t.MATCH_ID();
        kickoff = t.kickoff();
        actors = actors_;
        oracle = oracle_;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _gather(FactionToken token, address from, address to) internal {
        uint256 need = 54 ether;
        uint256 have = token.balanceOf(to);
        if (have >= need) return;
        uint256 give = token.balanceOf(from);
        if (give > need - have) give = need - have;
        if (give == 0) return;
        vm.prank(from);
        token.transfer(to, give);
    }

    function deposit(uint256 actorSeed, bool home, uint256 amount) external {
        address a = _actor(actorSeed);
        amount = bound(amount, 100 ether, 5_000 ether);
        vm.startPrank(a);
        bead.approve(address(pool), amount);
        try pool.deposit(matchId, home ? Faction.HOME : Faction.AWAY, amount) {} catch {}
        vm.stopPrank();
    }

    function withdrawEarly(uint256 actorSeed, bool home, uint256 amount) external {
        address a = _actor(actorSeed);
        FactionToken token = home ? homeToken : awayToken;
        amount = bound(amount, 1, token.balanceOf(a) + 1);
        vm.prank(a);
        try pool.withdrawEarly(matchId, home ? Faction.HOME : Faction.AWAY, amount) {
            ++earlyWithdrawals;
        } catch {}
    }

    function shuffleTokens(uint256 fromSeed, uint256 toSeed, bool home, uint256 amount) external {
        address from = _actor(fromSeed);
        FactionToken token = home ? homeToken : awayToken;
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(_actor(toSeed), amount);
    }

    function forge(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        // Pull 54 of each side from the other actors so forging is reachable despite the single-side lock.
        for (uint256 i; i < actors.length; ++i) {
            address other = actors[i];
            if (other == a) continue;
            _gather(homeToken, other, a);
            _gather(awayToken, other, a);
        }
        vm.prank(a);
        try necklace.forgeDiplomaticNecklace(matchId) {
            ++forges;
        } catch {}
    }

    function settle(uint256 outcomeSeed) external {
        if (pool.matchStatus(matchId) != MatchStatus.OPEN) return;
        vm.warp(kickoff);
        pool.lockMatch(matchId);
        Outcome outcome = Outcome(bound(outcomeSeed, 1, 4));
        vm.prank(oracle);
        pool.reportOutcomeProvisional(matchId, outcome);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(matchId);
    }

    function claim(uint256 actorSeed, bool home) external {
        MatchStatus s = pool.matchStatus(matchId);
        vm.roll(block.number + 60);
        Faction f = home ? Faction.HOME : Faction.AWAY;
        address a = _actor(actorSeed);
        if (s == MatchStatus.SETTLED) {
            vm.prank(a);
            try pool.claimSettlement(matchId, f) {
                ++settlementClaims;
            } catch {}
        } else if (s == MatchStatus.REFUNDED) {
            vm.prank(a);
            try pool.claimRefund(matchId, f) {
                ++refundClaims;
            } catch {}
        }
    }
}

contract PoolInvariantsTest is NecklaceBase {
    PoolHandler internal handler;

    function setUp() public override {
        super.setUp();
        address[] memory actors = new address[](3);
        actors[0] = alice;
        actors[1] = bob;
        actors[2] = carol;
        handler = new PoolHandler(this, actors, oracle);
        targetContract(address(handler));
    }

    /// Guards the invariant runs: the handler must be able to reach forge, settlement and claim paths.
    function test_HandlerReachesDeepPaths() public {
        handler.deposit(0, true, 1_000 ether);
        handler.deposit(1, false, 1_000 ether);
        handler.forge(0);
        assertEq(handler.forges(), 1);
        handler.settle(3);
        handler.claim(0, true);
        handler.claim(1, false);
        assertEq(handler.settlementClaims(), 2);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.SETTLED));
    }

    /// Every faction token outstanding is backed by at least one BEAD sitting in the pool.
    function invariant_PoolBacksAllFactionTokens() public view {
        uint256 outstanding = FactionToken(homeToken).totalSupply() + FactionToken(awayToken).totalSupply();
        assertGe(bead.balanceOf(address(pool)), outstanding);
    }

    /// Before settlement the staked accounting equals the live token supply on each side.
    function invariant_StakedTotalsTrackSupplyBeforeSettlement() public view {
        MatchStatus s = pool.matchStatus(MATCH_ID);
        if (s == MatchStatus.SETTLED || s == MatchStatus.REFUNDED) return;
        assertEq(pool.getMatch(MATCH_ID).totalHomeStaked, FactionToken(homeToken).totalSupply());
        assertEq(pool.getMatch(MATCH_ID).totalAwayStaked, FactionToken(awayToken).totalSupply());
    }

    /// BEAD supply can only shrink (forge burns), never grow past the cap.
    function invariant_BeadSupplyNeverExceedsCap() public view {
        assertLe(bead.totalSupply(), bead.cap());
    }

    /// The pool never holds less than the still-claimable truce bonus.
    function invariant_PoolCoversRemainingBonus() public view {
        uint256 owed = pool.bonusRemaining(MATCH_ID, Faction.HOME) + pool.bonusRemaining(MATCH_ID, Faction.AWAY);
        assertGe(bead.balanceOf(address(pool)), owed);
    }
}
