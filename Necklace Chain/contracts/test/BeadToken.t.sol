// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {BeadToken} from "../src/BeadToken.sol";
import {NecklaceBase} from "./NecklaceBase.sol";

contract MintableBead is BeadToken {
    constructor(address owner_, address[5] memory r) BeadToken(owner_, r) {}

    function mintForTest(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract BeadTokenTest is NecklaceBase {
    function test_FailMintOverHardCap() public {
        address[5] memory r = [alice, bob, carol, makeAddr("d"), makeAddr("e")];
        MintableBead m = new MintableBead(address(this), r);
        assertEq(m.totalSupply(), m.MAX_SUPPLY());
        vm.expectRevert(abi.encodeWithSelector(ERC20Capped.ERC20ExceededCap.selector, m.MAX_SUPPLY() + 1, m.MAX_SUPPLY()));
        m.mintForTest(alice, 1);
    }

    function test_RevertMintExceedingCosmicCap() public {
        assertEq(bead.cap(), 13_800_000_000 ether);
        assertEq(bead.totalSupply(), bead.cap());
    }

    function test_GenesisSplit() public {
        uint256 cap = bead.cap();
        assertEq(bead.balanceOf(makeAddr("team")), (cap * 15) / 100);
        assertEq(bead.balanceOf(makeAddr("seed")), (cap * 10) / 100);
        assertEq(bead.balanceOf(makeAddr("liq")), (cap * 15) / 100);
        assertEq(bead.balanceOf(makeAddr("treasury")), (cap * 20) / 100);
    }

    function test_PeaceTaxRouting() public {
        vm.prank(alice);
        bead.transfer(bob, 1_000 ether);
        assertEq(bead.balanceOf(address(forwarder)), 10 ether);
        assertEq(bead.balanceOf(bob), 100_000 ether + 990 ether);

        forwarder.forwardTaxes();
        assertEq(bead.balanceOf(PUBLIC_GOODS), 10 ether);
        assertEq(bead.balanceOf(address(forwarder)), 0);
    }

    function test_DustTransferReverts() public {
        vm.prank(alice);
        vm.expectRevert(BeadToken.DustTransfer.selector);
        bead.transfer(bob, 99 ether);
    }

    function test_FeeExemptSkipsTaxAndDust() public {
        bead.setFeeExempt(alice, true);
        vm.prank(alice);
        bead.transfer(bob, 1 ether);
        assertEq(bead.balanceOf(address(forwarder)), 0);
    }

    function test_ForwarderCanOnlyBeSetOnce() public {
        vm.expectRevert(BeadToken.ForwarderAlreadySet.selector);
        bead.setTreasuryForwarder(address(0x1234));
    }
}
