// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TierStaking} from "../src/TierStaking.sol";
import {NecklaceBase} from "./NecklaceBase.sol";

contract TierStakingTest is NecklaceBase {
    address internal resolver = makeAddr("resolver");

    function setUp() public override {
        super.setUp();
        staking.setResolver(resolver);
    }

    function _stake(address user, uint256 amount) internal {
        vm.startPrank(user);
        bead.approve(address(staking), amount);
        staking.stake(amount);
        vm.stopPrank();
    }

    function test_TierThresholds() public {
        assertEq(uint8(staking.tierOf(alice)), 0);
        _stake(alice, 18 ether);
        assertEq(uint8(staking.tierOf(alice)), 1);
        _stake(alice, 15 ether);
        assertEq(uint8(staking.tierOf(alice)), 2);
        assertTrue(staking.isChotki(alice));
        _stake(alice, 66 ether);
        assertEq(uint8(staking.tierOf(alice)), 3);
        assertTrue(staking.isCouncil(alice));
        assertEq(staking.councilCount(), 1);
    }

    function test_StakeAndUnstakeAreFeeFree() public {
        _stake(alice, 99 ether);
        assertEq(bead.balanceOf(address(staking)), 99 ether);
        uint256 before = bead.balanceOf(alice);
        vm.prank(alice);
        staking.unstake(99 ether);
        assertEq(bead.balanceOf(alice) - before, 99 ether);
        assertEq(staking.councilCount(), 0);
    }

    function test_CouncilSeatsCappedAtNinetyNine() public {
        for (uint256 i; i < 99; ++i) {
            address u = address(uint160(0x1000 + i));
            bead.setFeeExempt(address(this), true);
            bead.transfer(u, 99 ether);
            bead.setFeeExempt(address(this), false);
            _stake(u, 99 ether);
        }
        assertEq(staking.councilCount(), 99);
        vm.startPrank(alice);
        bead.approve(address(staking), 99 ether);
        vm.expectRevert(TierStaking.CouncilFull.selector);
        staking.stake(99 ether);
        vm.stopPrank();
    }

    function test_SlashedBondGoesToPublicGoods() public {
        _stake(alice, 33 ether);
        vm.startPrank(resolver);
        staking.lockBond(alice);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(TierStaking.BondLocked.selector);
        staking.unstake(1 ether);

        vm.prank(resolver);
        staking.slashBond(alice);
        assertEq(bead.balanceOf(PUBLIC_GOODS), 33 ether);
        assertEq(staking.stakeOf(alice), 0);
        assertFalse(staking.bondLocked(alice));
    }

    function test_ReleasedBondAllowsUnstake() public {
        _stake(alice, 33 ether);
        vm.startPrank(resolver);
        staking.lockBond(alice);
        staking.releaseBond(alice);
        vm.stopPrank();
        vm.prank(alice);
        staking.unstake(33 ether);
    }

    function test_OnlyChotkiCanPostBond() public {
        _stake(alice, 18 ether);
        vm.prank(resolver);
        vm.expectRevert(TierStaking.NotEligibleChallenger.selector);
        staking.lockBond(alice);
    }

    function test_OnlyResolverCanTouchBonds() public {
        _stake(alice, 33 ether);
        vm.expectRevert(TierStaking.NotResolver.selector);
        staking.lockBond(alice);
        vm.expectRevert(TierStaking.NotResolver.selector);
        staking.slashBond(alice);
    }
}
