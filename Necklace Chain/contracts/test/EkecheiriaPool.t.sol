// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FactionToken} from "../src/FactionToken.sol";
import {EkecheiriaPool} from "../src/EkecheiriaPool.sol";
import {MatchRegistry} from "../src/MatchRegistry.sol";
import {Faction, MatchStatus, Outcome} from "../src/interfaces/PoolTypes.sol";
import {NecklaceBase} from "./NecklaceBase.sol";

contract EkecheiriaPoolTest is NecklaceBase {
    function _settleWith(Outcome outcome) internal {
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, outcome);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(MATCH_ID);
    }

    // ---------------------------------------------------------------- deposits

    function test_DepositMintsNetAndRoutesTax() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        assertEq(FactionToken(homeToken).balanceOf(alice), 990 ether);
        assertEq(bead.balanceOf(PUBLIC_GOODS), 10 ether);
        assertEq(bead.balanceOf(address(forwarder)), 0);
        assertEq(pool.getMatch(MATCH_ID).totalHomeStaked, 990 ether);
    }

    function test_AffiliationLockBlocksOppositeSide() public {
        _deposit(alice, Faction.HOME, 200 ether);
        vm.startPrank(alice);
        bead.approve(address(pool), 200 ether);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.AffiliationLocked.selector, Faction.HOME));
        pool.deposit(MATCH_ID, Faction.AWAY, 200 ether);
        vm.stopPrank();
    }

    function test_DepositBelowDustReverts() public {
        vm.startPrank(alice);
        bead.approve(address(pool), 99 ether);
        vm.expectRevert(EkecheiriaPool.BelowMinimum.selector);
        pool.deposit(MATCH_ID, Faction.HOME, 99 ether);
        vm.stopPrank();
    }

    function test_DepositRejectsFactionNone() public {
        vm.startPrank(alice);
        bead.approve(address(pool), 200 ether);
        vm.expectRevert(EkecheiriaPool.InvalidFaction.selector);
        pool.deposit(MATCH_ID, Faction.NONE, 200 ether);
        vm.stopPrank();
    }

    function test_PoolCapIsCheckedOnNetAmount() public {
        // Net of a 100,000 deposit is 99,000, which fits; a second deposit pushes past the cap.
        _deposit(alice, Faction.HOME, 100_000 ether);
        vm.startPrank(bob);
        bead.approve(address(pool), 2_000 ether);
        vm.expectRevert(EkecheiriaPool.PoolCapExceeded.selector);
        pool.deposit(MATCH_ID, Faction.AWAY, 2_000 ether);
        vm.stopPrank();
    }

    function test_DepositAfterKickoffReverts() public {
        vm.warp(kickoff);
        vm.startPrank(alice);
        bead.approve(address(pool), 200 ether);
        vm.expectRevert(EkecheiriaPool.MatchNotOpen.selector);
        pool.deposit(MATCH_ID, Faction.HOME, 200 ether);
        vm.stopPrank();
    }

    function test_EarlyWithdrawalIsOneToOneOnTokens() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        uint256 before = bead.balanceOf(alice);
        vm.prank(alice);
        pool.withdrawEarly(MATCH_ID, Faction.HOME, 990 ether);
        assertEq(bead.balanceOf(alice) - before, 990 ether);
        assertEq(FactionToken(homeToken).totalSupply(), 0);
        assertEq(pool.getMatch(MATCH_ID).totalHomeStaked, 0);
    }

    // ------------------------------------------------------------ settlement

    function test_OracleChallengeWindowHoldsFunds() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.HOME_WIN);

        vm.warp(block.timestamp + 30 minutes - 1);
        vm.expectRevert(EkecheiriaPool.ChallengeWindowActive.selector);
        pool.finalizeSettlement(MATCH_ID);

        vm.roll(block.number + 60);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.PENDING_RESOLUTION));
        pool.claimSettlement(MATCH_ID, Faction.HOME);

        vm.warp(block.timestamp + 1);
        pool.finalizeSettlement(MATCH_ID);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.SETTLED));
    }

    function test_TruceBonusPaidWhenSymmetric() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        _settleWith(Outcome.DRAW);
        assertTrue(pool.getMatch(MATCH_ID).truceAchieved);

        vm.roll(block.number + 50);
        uint256 beforeA = bead.balanceOf(alice);
        vm.prank(alice);
        pool.claimSettlement(MATCH_ID, Faction.HOME);
        assertEq(bead.balanceOf(alice) - beforeA, 990 ether + 500 ether);
        assertEq(FactionToken(homeToken).balanceOf(alice), 0);
    }

    function test_SymmetryViolationRevertsTruce() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 100 ether); // 99 / (990 + 99) is about 9%, below 30%
        _settleWith(Outcome.HOME_WIN);
        assertFalse(pool.getMatch(MATCH_ID).truceAchieved);

        vm.roll(block.number + 50);
        uint256 beforeA = bead.balanceOf(alice);
        vm.prank(alice);
        pool.claimSettlement(MATCH_ID, Faction.HOME);
        assertEq(bead.balanceOf(alice) - beforeA, 990 ether);

        uint256 funderBefore = bead.balanceOf(address(this));
        pool.reclaimReward(MATCH_ID);
        assertEq(bead.balanceOf(address(this)) - funderBefore, REWARD);
    }

    function test_ClaimHonoursFiftyBlockHold() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(MATCH_ID);

        // depositBlock was set in this same block number (no roll), so the hold is still active.
        vm.prank(alice);
        vm.expectRevert(EkecheiriaPool.HoldPeriodActive.selector);
        pool.claimSettlement(MATCH_ID, Faction.HOME);

        vm.roll(block.number + 50);
        vm.prank(alice);
        pool.claimSettlement(MATCH_ID, Faction.HOME);
    }

    function test_TrucePoolRefund() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        _settleWith(Outcome.CANCELLED);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.REFUNDED));

        uint256 beforeA = bead.balanceOf(alice);
        uint256 beforeB = bead.balanceOf(bob);
        vm.prank(alice);
        pool.claimRefund(MATCH_ID, Faction.HOME);
        vm.prank(bob);
        pool.claimRefund(MATCH_ID, Faction.AWAY);
        assertEq(bead.balanceOf(alice) - beforeA, 990 ether);
        assertEq(bead.balanceOf(bob) - beforeB, 990 ether);

        uint256 funderBefore = bead.balanceOf(address(this));
        pool.reclaimReward(MATCH_ID);
        assertEq(bead.balanceOf(address(this)) - funderBefore, REWARD);
        assertEq(bead.balanceOf(address(pool)), 0);
    }

    function test_ClaimRefundRejectsFactionNone() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _settleWith(Outcome.CANCELLED);
        vm.prank(alice);
        vm.expectRevert(EkecheiriaPool.InvalidFaction.selector);
        pool.claimRefund(MATCH_ID, Faction.NONE);
    }

    function test_FailSafeRefundAfterOracleSilence() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        vm.warp(kickoff + 48 hours - 1);
        vm.expectRevert(EkecheiriaPool.FailSafeNotReady.selector);
        pool.failSafeRefund(MATCH_ID);

        vm.warp(kickoff + 48 hours);
        pool.failSafeRefund(MATCH_ID);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.REFUNDED));
    }

    function test_DisputedMatchResolvesThroughOracle() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.startPrank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.HOME_WIN);
        pool.markDisputed(MATCH_ID);
        vm.stopPrank();
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.DISPUTED));

        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.DISPUTED));
        pool.finalizeSettlement(MATCH_ID);

        vm.prank(oracle);
        pool.resolveDispute(MATCH_ID, Outcome.AWAY_WIN);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.SETTLED));
    }

    function test_DisputedMatchFailSafeAfterTimeout() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.startPrank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.HOME_WIN);
        pool.markDisputed(MATCH_ID);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        pool.failSafeRefund(MATCH_ID);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.REFUNDED));
    }

    function test_EmergencyRefundOnlyCouncil() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        vm.expectRevert(EkecheiriaPool.NotCouncilExecutor.selector);
        pool.emergencyRefund(MATCH_ID);

        vm.prank(council);
        pool.emergencyRefund(MATCH_ID);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.REFUNDED));
    }

    // -------------------------------------------------------- forge interplay

    function test_ForgedSharesRedistributeToRemainingHolders() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(carol, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 2_000 ether);

        vm.prank(bob);
        FactionToken(awayToken).transfer(alice, 54 ether);
        uint256 supplyBefore = bead.totalSupply();
        vm.prank(alice);
        necklace.forgeDiplomaticNecklace(MATCH_ID);
        assertEq(supplyBefore - bead.totalSupply(), 108 ether);

        _settleWith(Outcome.DRAW);
        vm.roll(block.number + 50);

        uint256 a0 = bead.balanceOf(alice);
        uint256 c0 = bead.balanceOf(carol);
        vm.prank(carol);
        pool.claimSettlement(MATCH_ID, Faction.HOME);
        vm.prank(alice);
        pool.claimSettlement(MATCH_ID, Faction.HOME);

        uint256 aliceHome = 990 ether - 54 ether;
        uint256 carolHome = 990 ether;
        uint256 totalBonus = (bead.balanceOf(alice) - a0 - aliceHome) + (bead.balanceOf(carol) - c0 - carolHome);
        // Entire home half (500) is paid out even though 54 tokens were forged away.
        assertApproxEqAbs(totalBonus, 500 ether, 10);
    }

    function test_OnForgeOnlyNecklace() public {
        vm.expectRevert(EkecheiriaPool.NotNecklace.selector);
        pool.onForge(MATCH_ID, 54 ether);
    }

    // ---------------------------------------------------------------- access

    function test_InitializeMatchOnlyRegistry() public {
        vm.expectRevert(EkecheiriaPool.NotRegistry.selector);
        pool.initializeMatch(99, address(1), address(2), block.timestamp + 1, 1, 0, address(this));
    }

    function test_ReportOutcomeOnlyOracle() public {
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.expectRevert(EkecheiriaPool.NotOracle.selector);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
    }

    function test_WireOnlyOnce() public {
        vm.expectRevert(EkecheiriaPool.AlreadyWired.selector);
        pool.wire(address(1), address(2), address(3));
    }
}

contract MatchRegistryTest is NecklaceBase {
    function test_CreateMatchFundsPoolAtomically() public view {
        assertEq(bead.balanceOf(address(pool)), REWARD);
        assertEq(pool.getMatch(MATCH_ID).rewardPool, REWARD);
        assertTrue(registry.isMatchActive(MATCH_ID));
    }

    function test_FactionTokensAreWiredToPoolAndNecklace() public view {
        assertEq(FactionToken(homeToken).pool(), address(pool));
        assertEq(FactionToken(homeToken).necklace(), address(necklace));
        assertTrue(homeToken != awayToken);
    }

    function test_StrangerCannotCreateMatch() public {
        vm.prank(alice);
        vm.expectRevert(MatchRegistry.NotAuthorized.selector);
        registry.createMatch(2, block.timestamp + 1 days, "A", "B", CAP, 0);
    }

    function test_BootstrapHandoverToCouncil() public {
        registry.renounceBootstrap();
        vm.expectRevert(MatchRegistry.NotAuthorized.selector);
        registry.createMatch(2, block.timestamp + 1 days, "A", "B", CAP, 0);

        vm.prank(council);
        registry.createMatch(2, block.timestamp + 1 days, "A", "B", CAP, 0);
        (address h,) = registry.getMatchTokens(2);
        assertTrue(h != address(0));
    }

    function test_DuplicateMatchIdReverts() public {
        vm.expectRevert(MatchRegistry.MatchExists.selector);
        registry.createMatch(MATCH_ID, block.timestamp + 1 days, "A", "B", CAP, 0);
    }

    function test_FactionTokenImplementationCannotBeInitialized() public {
        vm.expectRevert();
        factionImpl.initialize("x", "x", address(this), address(this));
    }

    function test_FactionTokenMintAndBurnAreGated() public {
        vm.expectRevert(FactionToken.Unauthorized.selector);
        FactionToken(homeToken).mint(alice, 1);
        vm.expectRevert(FactionToken.Unauthorized.selector);
        FactionToken(homeToken).burn(alice, 1);
    }
}
