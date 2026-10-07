// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {NecklaceBase} from "./NecklaceBase.sol";
import {EkecheiriaPool} from "../src/EkecheiriaPool.sol";
import {FactionToken} from "../src/FactionToken.sol";
import {Faction, Outcome} from "../src/interfaces/PoolTypes.sol";

/// @notice Hypothetical whole-protocol simulations that run the REAL contracts with deterministic pseudo-random crowds.
/// Run with: forge test --match-contract ScenarioSimulations -vv. The numbers feed the case studies in docs/index.html.
contract ScenarioSimulations is NecklaceBase {
    struct Crowd {
        address[] who;
        bool[] home;
        uint256[] gross;
    }

    struct Result {
        uint256 gross;
        uint256 tax;
        uint256 netHome;
        uint256 netAway;
        bool truce;
        uint256 bonusHome;
        uint256 bonusAway;
        uint256 reclaimed;
        int256 minBps;
        int256 maxBps;
        int256 avgBps;
    }

    uint256 private nextId = 100;

    function setUp() public override {
        super.setUp();
        bead.setFeeExempt(address(this), true); // lets the harness fund fans without tax
    }

    // ------------------------------------------------------------------ helpers

    function _open(uint256 cap, uint256 reward) internal returns (uint256 id) {
        id = nextId++;
        registry.createMatch(id, block.timestamp + 1 days, "North Red", "North White", cap, reward);
    }

    function _dep(uint256 id, address who, bool home, uint256 gross) internal {
        bead.transfer(who, gross);
        vm.startPrank(who);
        bead.approve(address(pool), gross);
        pool.deposit(id, home ? Faction.HOME : Faction.AWAY, gross);
        vm.stopPrank();
    }

    function _settle(uint256 id) internal {
        EkecheiriaPool.MatchState memory m = pool.getMatch(id);
        vm.warp(m.kickoffTime);
        pool.lockMatch(id);
        vm.prank(oracle);
        pool.reportOutcomeProvisional(id, Outcome.DRAW);
        skip(30 minutes + 1);
        pool.finalizeSettlement(id);
        vm.roll(block.number + 51);
    }

    /// @dev Claims for every fan and aggregates the result. Fans in `skipStats` still claim but are left out of the return stats.
    function _claimAll(uint256 id, Crowd memory c, uint256 taxBefore, uint256 skipMask)
        internal
        returns (Result memory r)
    {
        EkecheiriaPool.MatchState memory m = pool.getMatch(id);
        r.netHome = m.totalHomeStaked;
        r.netAway = m.totalAwayStaked;
        r.truce = m.truceAchieved;
        r.tax = bead.balanceOf(PUBLIC_GOODS) - taxBefore;

        int256 sum;
        uint256 counted;
        r.minBps = type(int256).max;
        r.maxBps = type(int256).min;
        for (uint256 i; i < c.who.length; ++i) {
            r.gross += c.gross[i];
            address token = c.home[i] ? m.homeToken : m.awayToken;
            uint256 bal = FactionToken(token).balanceOf(c.who[i]);
            if (bal == 0) continue;
            vm.prank(c.who[i]);
            pool.claimSettlement(id, c.home[i] ? Faction.HOME : Faction.AWAY);
            uint256 payout = bead.balanceOf(c.who[i]);
            uint256 bonus = payout - bal;
            if (c.home[i]) r.bonusHome += bonus;
            else r.bonusAway += bonus;
            if ((skipMask & (uint256(1) << i)) == 0) {
                int256 bps = int256((payout * 10_000) / c.gross[i]) - 10_000;
                if (bps < r.minBps) r.minBps = bps;
                if (bps > r.maxBps) r.maxBps = bps;
                sum += bps;
                ++counted;
            }
        }
        r.avgBps = counted == 0 ? int256(0) : sum / int256(counted);
    }

    function _crowd(uint256 salt, uint256 n, uint256 homePct) internal returns (Crowd memory c) {
        c.who = new address[](n);
        c.home = new bool[](n);
        c.gross = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            c.who[i] = address(uint160(uint256(keccak256(abi.encode("fan", salt, i)))));
            c.home[i] = uint256(keccak256(abi.encode("side", salt, i))) % 100 < homePct;
            uint256 s = 100 + (uint256(keccak256(abi.encode("stake", salt, i))) % 900); // 100..999 BEAD
            if (i % 20 == 0) s *= 5; // a few big fans
            c.gross[i] = s * 1 ether;
        }
    }

    function _depositCrowd(uint256 id, Crowd memory c) internal {
        for (uint256 i; i < c.who.length; ++i) _dep(id, c.who[i], c.home[i], c.gross[i]);
    }

    function _log(string memory tag, Result memory r, uint256 reward) internal pure {
        console2.log(tag);
        console2.log("  staked (gross BEAD)       ", r.gross / 1 ether);
        console2.log("  peace tax to Protocol Guild", r.tax / 1 ether);
        console2.log("  net Home / Away           ", r.netHome / 1 ether, r.netAway / 1 ether);
        console2.log("  truce achieved            ", r.truce);
        console2.log("  reward pool               ", reward / 1 ether);
        console2.log("  bonus paid Home / Away    ", r.bonusHome / 1 ether, r.bonusAway / 1 ether);
        if (r.netHome > 0) console2.log("  Home bonus per staked BEAD (bps)", (r.bonusHome * 10_000) / r.netHome);
        if (r.netAway > 0) console2.log("  Away bonus per staked BEAD (bps)", (r.bonusAway * 10_000) / r.netAway);
        console2.log("  fan net return bps min/avg/max");
        console2.logInt(r.minBps);
        console2.logInt(r.avgBps);
        console2.logInt(r.maxBps);
    }

    // ------------------------------------------------------------- scenario 1

    /// Healthy derby night: 150 fans, 55/45 split, a modest reward pool, two fans swap rival tokens and forge.
    function test_Scenario1_HealthyDerbyNight() public {
        uint256 reward = 3_000 ether;
        uint256 id = _open(300_000 ether, reward);
        Crowd memory c = _crowd(1, 150, 55);
        uint256 taxBefore = bead.balanceOf(PUBLIC_GOODS);
        _depositCrowd(id, c);

        // Find one Home and one Away big fan (stake x5) and let them swap 54 tokens so both can forge.
        uint256 hi = type(uint256).max;
        uint256 ai = type(uint256).max;
        for (uint256 i; i < 150; i += 20) {
            if (c.home[i] && hi == type(uint256).max) hi = i;
            if (!c.home[i] && ai == type(uint256).max) ai = i;
        }
        uint256 skipMask;
        uint256 supplyBefore = bead.totalSupply();
        if (hi != type(uint256).max && ai != type(uint256).max) {
            EkecheiriaPool.MatchState memory m0 = pool.getMatch(id);
            vm.prank(c.who[hi]);
            FactionToken(m0.homeToken).transfer(c.who[ai], 54 ether);
            vm.prank(c.who[ai]);
            FactionToken(m0.awayToken).transfer(c.who[hi], 54 ether);
            vm.prank(c.who[hi]);
            necklace.forgeDiplomaticNecklace(id);
            vm.prank(c.who[ai]);
            necklace.forgeDiplomaticNecklace(id);
            skipMask = (uint256(1) << hi) | (uint256(1) << ai);
            console2.log("forged necklaces: 2, BEAD burned", (supplyBefore - bead.totalSupply()) / 1 ether);
        }

        _settle(id);
        Result memory r = _claimAll(id, c, taxBefore, skipMask);
        _log("SCENARIO 1 - healthy derby night", r, reward);
        assertTrue(r.truce);
    }

    // ------------------------------------------------------------- scenario 2

    /// Lopsided home crowd: 150 fans, 90% Home. No truce, the funder reclaims the reward, fans only lose the 1% tax.
    function test_Scenario2_LopsidedHomeCrowd() public {
        uint256 reward = 3_000 ether;
        uint256 id = _open(300_000 ether, reward);
        Crowd memory c = _crowd(2, 150, 90);
        uint256 taxBefore = bead.balanceOf(PUBLIC_GOODS);
        _depositCrowd(id, c);
        _settle(id);
        uint256 funderBefore = bead.balanceOf(address(this));
        pool.reclaimReward(id);
        uint256 reclaimed = bead.balanceOf(address(this)) - funderBefore;
        Result memory r = _claimAll(id, c, taxBefore, 0);
        r.reclaimed = reclaimed;
        _log("SCENARIO 2 - lopsided home crowd", r, reward);
        console2.log("  reward returned to funder  ", reclaimed / 1 ether);
        assertFalse(r.truce);
    }

    /// Sweep of minority share with a fixed 100,000 BEAD pool and a 3,000 BEAD reward.
    function test_Scenario2b_MinorityShareSweep() public {
        uint256[8] memory minorityPct = [uint256(10), 20, 25, 29, 30, 35, 45, 50];
        console2.log("SWEEP minority share % -> truce, majority bonus bps, minority bonus bps (100k gross, 3k reward)");
        for (uint256 k; k < minorityPct.length; ++k) {
            uint256 m = minorityPct[k];
            uint256 id = _open(300_000 ether, 3_000 ether);
            address big = address(uint160(0xA000 + k));
            address small = address(uint160(0xB000 + k));
            _dep(id, big, true, (100 - m) * 1_000 ether);
            _dep(id, small, false, m * 1_000 ether);
            _settle(id);
            EkecheiriaPool.MatchState memory st = pool.getMatch(id);
            uint256 bigBal = FactionToken(st.homeToken).balanceOf(big);
            uint256 smallBal = FactionToken(st.awayToken).balanceOf(small);
            vm.prank(big);
            pool.claimSettlement(id, Faction.HOME);
            vm.prank(small);
            pool.claimSettlement(id, Faction.AWAY);
            console2.log("  minority %", m);
            console2.log("    truce", st.truceAchieved);
            console2.log("    majority bonus bps", ((bead.balanceOf(big) - bigBal) * 10_000) / bigBal);
            console2.log("    minority bonus bps", ((bead.balanceOf(small) - smallBal) * 10_000) / smallBal);
        }
    }

    // ------------------------------------------------------------- scenario 3

    function _honestCrowd(uint256 salt) internal pure returns (Crowd memory c) {
        c.who = new address[](70);
        c.home = new bool[](70);
        c.gross = new uint256[](70);
        for (uint256 i; i < 70; ++i) {
            c.who[i] = address(uint160(uint256(keccak256(abi.encode("honest", salt, i)))));
            c.home[i] = i < 60; // 60 Home fans, 10 Away fans, 1,000 BEAD each
            c.gross[i] = 1_000 ether;
        }
    }

    function _whaleRun(string memory tag, uint256 reward, uint256 whaleGross) internal {
        uint256 id = _open(400_000 ether, reward);
        Crowd memory c = _honestCrowd(id);
        uint256 taxBefore = bead.balanceOf(PUBLIC_GOODS);
        _depositCrowd(id, c);
        address whale = makeAddr(string.concat("whale", tag));
        if (whaleGross > 0) _dep(id, whale, false, whaleGross);
        _settle(id);

        uint256 funderBefore = bead.balanceOf(address(this));
        EkecheiriaPool.MatchState memory st = pool.getMatch(id);
        if (!st.truceAchieved) pool.reclaimReward(id);
        uint256 reclaimed = bead.balanceOf(address(this)) - funderBefore;

        uint256 whaleNet;
        if (whaleGross > 0) {
            whaleNet = FactionToken(st.awayToken).balanceOf(whale);
            vm.prank(whale);
            pool.claimSettlement(id, Faction.AWAY);
        }
        Result memory r = _claimAll(id, c, taxBefore, 0);
        console2.log(tag);
        console2.log("  reward pool / truce", reward / 1 ether, r.truce);
        console2.log("  honest fans avg net return bps");
        console2.logInt(r.avgBps);
        console2.log("  reward returned to funder   ", reclaimed / 1 ether);
        if (whaleGross > 0) {
            int256 whaleProfit = int256(bead.balanceOf(whale)) - int256(whaleGross);
            console2.log("  whale deposit (gross) / net stake", whaleGross / 1 ether, whaleNet / 1 ether);
            console2.log("  whale share of Away side bps", (whaleNet * 10_000) / st.totalAwayStaked);
            console2.log("  whale profit (BEAD, after the 1% tax)");
            console2.logInt(whaleProfit / 1 ether);
            console2.log("  whale profit bps of deposit");
            console2.logInt((whaleProfit * 10_000) / int256(whaleGross));
        }
    }

    /// A capital-rich wallet pads the weak side just past 30% to switch the bonus on and capture part of it.
    function test_Scenario3_WhalePadsTheMinoritySide() public {
        _whaleRun("S3 baseline: lopsided, no whale", 3_000 ether, 0);
        _whaleRun("S3 whale pads Away, reward 3000", 3_000 ether, 16_300 ether);
        _whaleRun("S3 whale pads Away, reward 500", 500 ether, 16_300 ether);
    }
}
