// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FactionToken} from "../src/FactionToken.sol";
import {BeadToken} from "../src/BeadToken.sol";
import {EkecheiriaPool} from "../src/EkecheiriaPool.sol";
import {Faction, MatchStatus, Outcome} from "../src/interfaces/PoolTypes.sol";
import {NecklaceBase} from "./NecklaceBase.sol";

contract FuzzTest is NecklaceBase {
    function testFuzz_TransferTaxIsExactlyOnePercent(uint256 value) public {
        value = bound(value, 100 ether, 50_000 ether);
        uint256 recipientBefore = bead.balanceOf(bob);
        vm.prank(alice);
        bead.transfer(bob, value);
        uint256 fee = (value * 100) / 10_000;
        assertEq(bead.balanceOf(address(forwarder)), fee);
        assertEq(bead.balanceOf(bob) - recipientBefore, value - fee);
    }

    function testFuzz_TransfersBelowDustRevert(uint256 value) public {
        value = bound(value, 0, 100 ether - 1);
        vm.prank(alice);
        vm.expectRevert(BeadToken.DustTransfer.selector);
        bead.transfer(bob, value);
    }

    function testFuzz_DepositSplitsTaxAndNetExactly(uint256 amount) public {
        amount = bound(amount, 100 ether, 50_000 ether);
        uint256 poolBefore = bead.balanceOf(address(pool));
        _deposit(alice, Faction.HOME, amount);
        uint256 tax = (amount * 100) / 10_000;
        assertEq(bead.balanceOf(PUBLIC_GOODS), tax);
        assertEq(FactionToken(homeToken).balanceOf(alice), amount - tax);
        assertEq(bead.balanceOf(address(pool)) - poolBefore, amount - tax);
    }

    function testFuzz_TruceFlagMatchesThirtyPercentRule(uint256 homeAmt, uint256 awayAmt) public {
        homeAmt = bound(homeAmt, 100 ether, 40_000 ether);
        awayAmt = bound(awayAmt, 100 ether, 40_000 ether);
        _deposit(alice, Faction.HOME, homeAmt);
        _deposit(bob, Faction.AWAY, awayAmt);

        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.DRAW);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(MATCH_ID);

        uint256 home = homeAmt - (homeAmt * 100) / 10_000;
        uint256 away = awayAmt - (awayAmt * 100) / 10_000;
        uint256 minSide = home < away ? home : away;
        bool expected = minSide * 10_000 >= 3000 * (home + away);
        assertEq(pool.getMatch(MATCH_ID).truceAchieved, expected);
    }

    function testFuzz_EveryoneGetsPrincipalBackAfterRefund(uint256 homeAmt, uint256 awayAmt) public {
        homeAmt = bound(homeAmt, 100 ether, 40_000 ether);
        awayAmt = bound(awayAmt, 100 ether, 40_000 ether);
        _deposit(alice, Faction.HOME, homeAmt);
        _deposit(bob, Faction.AWAY, awayAmt);

        vm.prank(council);
        pool.emergencyRefund(MATCH_ID);

        uint256 a0 = bead.balanceOf(alice);
        uint256 b0 = bead.balanceOf(bob);
        vm.prank(alice);
        pool.claimRefund(MATCH_ID, Faction.HOME);
        vm.prank(bob);
        pool.claimRefund(MATCH_ID, Faction.AWAY);
        assertEq(bead.balanceOf(alice) - a0, homeAmt - (homeAmt * 100) / 10_000);
        assertEq(bead.balanceOf(bob) - b0, awayAmt - (awayAmt * 100) / 10_000);
    }

    function testFuzz_BonusNeverExceedsRewardPool(uint256 homeAmt, uint256 awayAmt, uint256 extraHolders) public {
        homeAmt = bound(homeAmt, 1_000 ether, 20_000 ether);
        awayAmt = bound(awayAmt, 1_000 ether, 20_000 ether);
        uint256 carolAmt = bound(extraHolders, 100 ether, 20_000 ether);
        _deposit(alice, Faction.HOME, homeAmt);
        _deposit(carol, Faction.HOME, carolAmt);
        _deposit(bob, Faction.AWAY, awayAmt);

        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        vm.prank(oracle);
        pool.reportOutcomeProvisional(MATCH_ID, Outcome.HOME_WIN);
        vm.warp(block.timestamp + 30 minutes);
        pool.finalizeSettlement(MATCH_ID);
        vm.roll(block.number + 60);

        uint256 poolBefore = bead.balanceOf(address(pool));
        vm.prank(alice);
        pool.claimSettlement(MATCH_ID, Faction.HOME);
        vm.prank(carol);
        pool.claimSettlement(MATCH_ID, Faction.HOME);
        vm.prank(bob);
        pool.claimSettlement(MATCH_ID, Faction.AWAY);

        // All principal plus at most the reward pool left the contract.
        uint256 paid = poolBefore - bead.balanceOf(address(pool));
        uint256 principal = (homeAmt - homeAmt / 100) + (carolAmt - carolAmt / 100) + (awayAmt - awayAmt / 100);
        assertLe(paid, principal + REWARD);
        assertGe(paid, principal);
    }
}
