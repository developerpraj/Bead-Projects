// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {CosmicNecklace} from "../src/CosmicNecklace.sol";
import {FactionToken} from "../src/FactionToken.sol";
import {Faction} from "../src/interfaces/PoolTypes.sol";
import {NecklaceBase} from "./NecklaceBase.sol";

contract CosmicNecklaceTest is NecklaceBase {
    function _forgeAsAlice() internal returns (uint256 tokenId) {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        vm.prank(bob);
        FactionToken(awayToken).transfer(alice, 54 ether);
        vm.prank(alice);
        tokenId = necklace.forgeDiplomaticNecklace(MATCH_ID);
    }

    function test_ForgeRequiresOpposingFactions() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 54 ether)
        );
        necklace.forgeDiplomaticNecklace(MATCH_ID);
    }

    function test_DualFactionBurnAccuracy() public {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        vm.prank(bob);
        FactionToken(awayToken).transfer(alice, 54 ether);

        uint256 homeBefore = FactionToken(homeToken).totalSupply();
        uint256 awayBefore = FactionToken(awayToken).totalSupply();

        vm.prank(alice);
        uint256 id = necklace.forgeDiplomaticNecklace(MATCH_ID);

        assertEq(homeBefore - FactionToken(homeToken).totalSupply(), 54 ether);
        assertEq(awayBefore - FactionToken(awayToken).totalSupply(), 54 ether);
        assertEq(FactionToken(awayToken).balanceOf(alice), 0);
        assertEq(necklace.ownerOf(id), alice);
        assertEq(necklace.balanceOf(alice), 1);
    }

    function test_ForgeWorksWithoutApproval() public {
        assertEq(_forgeAsAlice(), 1);
    }

    function test_ForgeUnknownMatchReverts() public {
        vm.expectRevert(CosmicNecklace.InvalidMatch.selector);
        necklace.forgeDiplomaticNecklace(777);
    }

    function test_TenureUtilitiesScaleThenCap() public {
        uint256 id = _forgeAsAlice();
        assertEq(necklace.getVotingWeight(id), 1);
        assertEq(necklace.getFeeDiscountBps(id), 0);
        assertEq(necklace.getRank(id), "Initiate");

        skip(108 days);
        assertEq(necklace.getVotingWeight(id), 2);
        assertEq(necklace.getFeeDiscountBps(id), 1500);
        assertEq(necklace.getRank(id), "Ascendant");

        skip(108 days);
        assertEq(necklace.getRank(id), "Solar");

        skip(108 days);
        assertEq(necklace.getFeeDiscountBps(id), 3000);
        assertEq(necklace.getRank(id), "Galactic");

        skip(2_000 days);
        assertEq(necklace.getVotingWeight(id), 6);
        assertEq(necklace.getFeeDiscountBps(id), 3000);
    }

    function test_TransferResetsHoldingMultiplier() public {
        uint256 id = _forgeAsAlice();
        skip(324 days);
        assertEq(necklace.getVotingWeight(id), 4);

        vm.prank(alice);
        necklace.transferFrom(alice, carol, id);

        assertEq(necklace.getVotingWeight(id), 1);
        assertEq(necklace.getFeeDiscountBps(id), 0);
    }
}
