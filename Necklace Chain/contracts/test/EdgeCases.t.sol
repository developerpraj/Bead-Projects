// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FactionToken} from "../src/FactionToken.sol";
import {EkecheiriaPool} from "../src/EkecheiriaPool.sol";
import {MatchRegistry} from "../src/MatchRegistry.sol";
import {TreasuryForwarder} from "../src/TreasuryForwarder.sol";
import {CosmicNecklace} from "../src/CosmicNecklace.sol";
import {Faction, MatchStatus, Outcome} from "../src/interfaces/PoolTypes.sol";
import {NecklaceBase} from "./NecklaceBase.sol";

/// @dev Negative paths and edge cases for the state machine.
contract PoolEdgeCasesTest is NecklaceBase {
    function _lockedWithDeposits() internal {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
    }

    function test_UnknownMatchReverts() public {
        vm.expectRevert(EkecheiriaPool.MatchNotFound.selector);
        pool.lockMatch(999);
        vm.expectRevert(EkecheiriaPool.MatchNotFound.selector);
        pool.matchStatus(999);
    }

    function test_LockBeforeKickoffReverts() public {
        vm.expectRevert(EkecheiriaPool.KickoffNotReached.selector);
        pool.lockMatch(MATCH_ID);
    }

    function test_LockTwiceReverts() public {
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.LOCKED));
        pool.lockMatch(MATCH_ID);
    }

    function test_ReportOutcomeNoneReverts() public {
        _lockedWithDeposits();
        vm.prank(oracle);
        vm.expectRevert(EkecheiriaPool.InvalidOutcome.selector);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.NONE);
    }

    function test_NonCancelReportBeforeKickoffReverts() public {
        vm.prank(oracle);
        vm.expectRevert(EkecheiriaPool.KickoffNotReached.selector);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.HOME_WIN);
    }

    function test_CancellationMayBeReportedBeforeKickoff() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.CANCELLED);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(MATCH_ID);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.REFUNDED));
    }

    function test_ReportTwiceReverts() public {
        _lockedWithDeposits();
        vm.startPrank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.PENDING_RESOLUTION));
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        vm.stopPrank();
    }

    function test_MarkDisputedOutsideWindowAndWrongStatusRevert() public {
        _lockedWithDeposits();
        vm.startPrank(oracle);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.LOCKED));
        pool.markDisputed(MATCH_ID);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        vm.warp(block.timestamp + 30 minutes);
        vm.expectRevert(EkecheiriaPool.ChallengeWindowClosed.selector);
        pool.markDisputed(MATCH_ID);
        vm.stopPrank();
    }

    function test_ResolveDisputeNeedsDisputedStatusAndRealOutcome() public {
        _lockedWithDeposits();
        vm.startPrank(oracle);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.LOCKED));
        pool.resolveDispute(MATCH_ID, Outcome.DRAW);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        pool.markDisputed(MATCH_ID);
        vm.expectRevert(EkecheiriaPool.InvalidOutcome.selector);
        pool.resolveDispute(MATCH_ID, Outcome.NONE);
        vm.stopPrank();
    }

    function test_FailSafeRejectsSettledMatches() public {
        _lockedWithDeposits();
        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(MATCH_ID);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.SETTLED));
        pool.failSafeRefund(MATCH_ID);
        vm.prank(council);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.SETTLED));
        pool.emergencyRefund(MATCH_ID);
    }

    function test_ClaimsRejectEmptyHoldersAndWrongStatus() public {
        _lockedWithDeposits();
        vm.roll(block.number + 60);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.LOCKED));
        pool.claimSettlement(MATCH_ID, Faction.HOME);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.LOCKED));
        pool.claimRefund(MATCH_ID, Faction.HOME);

        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(MATCH_ID);

        vm.prank(carol); // never staked
        vm.expectRevert(EkecheiriaPool.NothingToClaim.selector);
        pool.claimSettlement(MATCH_ID, Faction.HOME);
        vm.prank(alice);
        vm.expectRevert(EkecheiriaPool.InvalidFaction.selector);
        pool.claimSettlement(MATCH_ID, Faction.NONE);
    }

    function test_RewardCanOnlyBeReclaimedOnceAndNotWhenTruceHeld() public {
        _lockedWithDeposits();
        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(MATCH_ID);
        // Symmetric pool kept its truce, so the reward is still owed to holders.
        vm.expectRevert(abi.encodeWithSelector(EkecheiriaPool.WrongStatus.selector, MatchStatus.SETTLED));
        pool.reclaimReward(MATCH_ID);
    }

    function test_ReclaimRewardOnlyOnce() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        vm.prank(council);
        pool.emergencyRefund(MATCH_ID);
        pool.reclaimReward(MATCH_ID);
        vm.expectRevert(EkecheiriaPool.NothingToReclaim.selector);
        pool.reclaimReward(MATCH_ID);
    }

    function test_EarlyWithdrawGuards() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        vm.startPrank(alice);
        vm.expectRevert(EkecheiriaPool.InvalidFaction.selector);
        pool.withdrawEarly(MATCH_ID, Faction.NONE, 1 ether);
        vm.expectRevert(EkecheiriaPool.NothingToClaim.selector);
        pool.withdrawEarly(MATCH_ID, Faction.HOME, 0);
        vm.stopPrank();

        vm.warp(kickoff);
        vm.prank(alice);
        vm.expectRevert(EkecheiriaPool.MatchNotOpen.selector);
        pool.withdrawEarly(MATCH_ID, Faction.HOME, 1 ether);
    }

    function test_InitializeMatchValidation() public {
        vm.startPrank(address(registry));
        vm.expectRevert(EkecheiriaPool.MatchAlreadyExists.selector);
        pool.initializeMatch(MATCH_ID, address(1), address(2), block.timestamp + 1 days, 1, 0, address(this));
        vm.expectRevert(EkecheiriaPool.ZeroAddress.selector);
        pool.initializeMatch(50, address(0), address(2), block.timestamp + 1 days, 1, 0, address(this));
        vm.expectRevert(EkecheiriaPool.InvalidKickoff.selector);
        pool.initializeMatch(51, address(1), address(2), block.timestamp, 1, 0, address(this));
        vm.stopPrank();
    }

    function test_ConstructorAndWireRejectZeroAddresses() public {
        vm.expectRevert(EkecheiriaPool.ZeroAddress.selector);
        new EkecheiriaPool(address(0), address(forwarder), council);

        EkecheiriaPool fresh = new EkecheiriaPool(address(bead), address(forwarder), council);
        vm.prank(alice);
        vm.expectRevert(EkecheiriaPool.NotDeployer.selector);
        fresh.wire(address(1), address(2), address(3));
        vm.expectRevert(EkecheiriaPool.ZeroAddress.selector);
        fresh.wire(address(0), address(2), address(3));
    }

    function test_ForgeAfterSettlementStillBurnsPrincipal() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        vm.prank(bob);
        FactionToken(awayToken).transfer(alice, 54 ether);
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(MATCH_ID);

        uint256 supplyBefore = bead.totalSupply();
        uint256 homeStakedBefore = pool.getMatch(MATCH_ID).totalHomeStaked;
        vm.prank(alice);
        necklace.forgeDiplomaticNecklace(MATCH_ID);
        assertEq(supplyBefore - bead.totalSupply(), 108 ether);
        // Settled totals stay frozen; only live token supply shrinks.
        assertEq(pool.getMatch(MATCH_ID).totalHomeStaked, homeStakedBefore);
    }
}

contract RegistryAndForwarderEdgeCasesTest is NecklaceBase {
    function test_RegistryConstructorRejectsZeroAddress() public {
        vm.expectRevert(MatchRegistry.ZeroAddress.selector);
        new MatchRegistry(address(0), address(bead), address(factionImpl), council);
    }

    function test_OnlyDeployerCanRenounceBootstrapAndOnlyOnce() public {
        vm.prank(alice);
        vm.expectRevert(MatchRegistry.NotDeployer.selector);
        registry.renounceBootstrap();
        registry.renounceBootstrap();
        vm.expectRevert(MatchRegistry.BootstrapAlreadyRenounced.selector);
        registry.renounceBootstrap();
    }

    function test_IsMatchActiveTracksLifecycle() public {
        assertFalse(registry.isMatchActive(77));
        assertTrue(registry.isMatchActive(MATCH_ID));
        vm.prank(council);
        pool.emergencyRefund(MATCH_ID);
        assertFalse(registry.isMatchActive(MATCH_ID));
    }

    function test_ForwarderRejectsZeroAddressesAndIgnoresEmptyBalance() public {
        vm.expectRevert(TreasuryForwarder.ZeroAddress.selector);
        new TreasuryForwarder(address(0), PUBLIC_GOODS);
        vm.expectRevert(TreasuryForwarder.ZeroAddress.selector);
        new TreasuryForwarder(address(bead), address(0));
        forwarder.forwardTaxes(); // empty balance is a no-op, not a revert
    }

    function test_NecklaceRejectsTenureQueriesForUnknownTokens() public {
        vm.expectRevert();
        necklace.getTenureCycles(1);
    }
}
