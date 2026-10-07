// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GaslessPaymaster} from "../src/GaslessPaymaster.sol";
import {UserOperation, PostOpMode} from "../src/interfaces/IEntryPointV06.sol";
import {Faction} from "../src/interfaces/PoolTypes.sol";
import {NecklaceBase} from "./NecklaceBase.sol";

contract MockEntryPointV06 {
    mapping(address => uint256) public balanceOf;
    uint256 public stake;
    uint32 public unstakeDelay;
    bool public unlocked;

    function depositTo(address account) external payable {
        balanceOf[account] += msg.value;
    }

    function withdrawTo(address payable to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        to.transfer(amount);
    }

    function addStake(uint32 delay) external payable {
        stake += msg.value;
        unstakeDelay = delay;
    }

    function unlockStake() external {
        unlocked = true;
    }

    function withdrawStake(address payable to) external {
        require(unlocked, "stake locked");
        uint256 s = stake;
        stake = 0;
        to.transfer(s);
    }
}

contract GaslessPaymasterTest is NecklaceBase {
    MockEntryPointV06 internal entryPoint;
    GaslessPaymaster internal paymaster;
    address internal factory = makeAddr("walletFactory");
    address internal wallet = makeAddr("smartWallet");

    bytes4 internal constant EXECUTE = bytes4(keccak256("execute(address,uint256,bytes)"));
    bytes4 internal constant EXECUTE_BATCH = bytes4(keccak256("executeBatch((address,uint256,bytes)[])"));

    function setUp() public override {
        super.setUp();
        entryPoint = new MockEntryPointV06();
        paymaster = new GaslessPaymaster(address(entryPoint), factory, 0.001 ether, 0.002 ether, 0.003 ether);
        paymaster.setAllowed(address(bead), bead.approve.selector, true);
        paymaster.setAllowed(address(pool), pool.deposit.selector, true);
        paymaster.setAllowed(address(necklace), necklace.forgeDiplomaticNecklace.selector, true);
    }

    function _op(address sender, bytes memory callData, bytes memory initCode)
        internal
        pure
        returns (UserOperation memory op)
    {
        op.sender = sender;
        op.callData = callData;
        op.initCode = initCode;
    }

    function _single(address target, uint256 value, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(EXECUTE, target, value, data);
    }

    function _depositCall() internal view returns (bytes memory) {
        return abi.encodeCall(pool.deposit, (MATCH_ID, Faction.HOME, 200 ether));
    }

    function _validate(UserOperation memory op, uint256 maxCost) internal returns (bytes memory ctx) {
        vm.prank(address(entryPoint));
        (ctx,) = paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
    }

    function test_SponsorsWhitelistedCall() public {
        bytes memory ctx = _validate(_op(wallet, _single(address(pool), 0, _depositCall()), ""), 0.0005 ether);
        assertEq(paymaster.senderSpent(block.timestamp / 1 days, wallet), 0.0005 ether);
        assertGt(ctx.length, 0);
    }

    function test_SponsorsApproveThenDepositBatch() public {
        GaslessPaymaster.Call[] memory calls = new GaslessPaymaster.Call[](2);
        calls[0] = GaslessPaymaster.Call(address(bead), 0, abi.encodeCall(bead.approve, (address(pool), 200 ether)));
        calls[1] = GaslessPaymaster.Call(address(pool), 0, _depositCall());
        _validate(_op(wallet, abi.encodeWithSelector(EXECUTE_BATCH, calls), ""), 0.0005 ether);
    }

    function test_RejectsUnlistedTarget() public {
        bytes memory data = abi.encodeCall(bead.transfer, (bob, 100 ether));
        vm.prank(address(entryPoint));
        vm.expectRevert(abi.encodeWithSelector(GaslessPaymaster.NotSponsored.selector, address(bead), bead.transfer.selector));
        paymaster.validatePaymasterUserOp(_op(wallet, _single(address(bead), 0, data), ""), bytes32(0), 0.0005 ether);
    }

    function test_RejectsValueTransfers() public {
        vm.prank(address(entryPoint));
        vm.expectRevert(GaslessPaymaster.ValueNotAllowed.selector);
        paymaster.validatePaymasterUserOp(
            _op(wallet, _single(address(pool), 1, _depositCall()), ""), bytes32(0), 0.0005 ether
        );
    }

    function test_BatchWithOneBadCallIsRejected() public {
        GaslessPaymaster.Call[] memory calls = new GaslessPaymaster.Call[](2);
        calls[0] = GaslessPaymaster.Call(address(pool), 0, _depositCall());
        calls[1] = GaslessPaymaster.Call(address(bead), 0, abi.encodeCall(bead.transfer, (bob, 100 ether)));
        vm.prank(address(entryPoint));
        vm.expectRevert(abi.encodeWithSelector(GaslessPaymaster.NotSponsored.selector, address(bead), bead.transfer.selector));
        paymaster.validatePaymasterUserOp(
            _op(wallet, abi.encodeWithSelector(EXECUTE_BATCH, calls), ""), bytes32(0), 0.0005 ether
        );
    }

    function test_RejectsUnknownCallDataShape() public {
        vm.prank(address(entryPoint));
        vm.expectRevert(GaslessPaymaster.BadCallData.selector);
        paymaster.validatePaymasterUserOp(_op(wallet, hex"deadbeef", ""), bytes32(0), 0.0005 ether);
    }

    function test_OnlyEntryPointCanValidate() public {
        vm.expectRevert(GaslessPaymaster.NotEntryPoint.selector);
        paymaster.validatePaymasterUserOp(_op(wallet, _single(address(pool), 0, _depositCall()), ""), bytes32(0), 1);
    }

    function test_RejectsCostAbovePerOpLimit() public {
        vm.prank(address(entryPoint));
        vm.expectRevert(GaslessPaymaster.CostTooHigh.selector);
        paymaster.validatePaymasterUserOp(
            _op(wallet, _single(address(pool), 0, _depositCall()), ""), bytes32(0), 0.002 ether
        );
    }

    function test_SenderBudgetEnforcedThenResetsNextDay() public {
        UserOperation memory op = _op(wallet, _single(address(pool), 0, _depositCall()), "");
        _validate(op, 0.001 ether);
        _validate(op, 0.001 ether);
        vm.prank(address(entryPoint));
        vm.expectRevert(GaslessPaymaster.SenderBudgetExceeded.selector);
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0.001 ether);

        skip(1 days);
        _validate(op, 0.001 ether);
    }

    function test_GlobalBudgetStopsSybilWallets() public {
        _validate(_op(makeAddr("w1"), _single(address(pool), 0, _depositCall()), ""), 0.001 ether);
        _validate(_op(makeAddr("w2"), _single(address(pool), 0, _depositCall()), ""), 0.001 ether);
        _validate(_op(makeAddr("w3"), _single(address(pool), 0, _depositCall()), ""), 0.001 ether);
        vm.prank(address(entryPoint));
        vm.expectRevert(GaslessPaymaster.GlobalBudgetExceeded.selector);
        paymaster.validatePaymasterUserOp(
            _op(makeAddr("w4"), _single(address(pool), 0, _depositCall()), ""), bytes32(0), 0.001 ether
        );
    }

    function test_PostOpRefundsUnusedBudget() public {
        bytes memory ctx = _validate(_op(wallet, _single(address(pool), 0, _depositCall()), ""), 0.001 ether);
        vm.prank(address(entryPoint));
        paymaster.postOp(PostOpMode.opSucceeded, ctx, 0.0004 ether);
        assertEq(paymaster.senderSpent(block.timestamp / 1 days, wallet), 0.0004 ether);
        assertEq(paymaster.globalSpent(block.timestamp / 1 days), 0.0004 ether);
    }

    function test_InitCodeMustComeFromKnownFactory() public {
        bytes memory good = abi.encodePacked(factory, hex"1234");
        _validate(_op(wallet, _single(address(pool), 0, _depositCall()), good), 0.0005 ether);

        bytes memory bad = abi.encodePacked(makeAddr("evil"), hex"1234");
        vm.prank(address(entryPoint));
        vm.expectRevert(GaslessPaymaster.UnknownFactory.selector);
        paymaster.validatePaymasterUserOp(
            _op(wallet, _single(address(pool), 0, _depositCall()), bad), bytes32(0), 0.0005 ether
        );
    }

    function test_EthSentToPaymasterFundsEntryPointDeposit() public {
        vm.deal(address(this), 0.05 ether);
        (bool ok,) = address(paymaster).call{value: 0.05 ether}("");
        assertTrue(ok);
        assertEq(entryPoint.balanceOf(address(paymaster)), 0.05 ether);
    }

    function test_AddStakeForwardsValueAndDelayToEntryPoint() public {
        vm.deal(address(this), 1 ether);
        paymaster.addStake{value: 0.01 ether}(1 days);
        assertEq(entryPoint.stake(), 0.01 ether);
        assertEq(entryPoint.unstakeDelay(), 1 days);
    }

    function test_DepositAndStakeAreSeparateBalances() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(paymaster).call{value: 0.04 ether}("");
        assertTrue(ok);
        paymaster.addStake{value: 0.01 ether}(1 days);
        assertEq(entryPoint.balanceOf(address(paymaster)), 0.04 ether);
        assertEq(entryPoint.stake(), 0.01 ether);
    }

    function test_StakeWithdrawalRequiresUnlockFirst() public {
        vm.deal(address(this), 1 ether);
        paymaster.addStake{value: 0.01 ether}(1 days);
        vm.expectRevert(bytes("stake locked"));
        paymaster.withdrawStake(payable(address(this)));

        paymaster.unlockStake();
        uint256 before = address(this).balance;
        paymaster.withdrawStake(payable(address(this)));
        assertEq(address(this).balance - before, 0.01 ether);
    }

    function test_OnlyOwnerCanManageStake() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        vm.expectRevert(GaslessPaymaster.NotOwner.selector);
        paymaster.addStake{value: 0.01 ether}(1 days);
        vm.expectRevert(GaslessPaymaster.NotOwner.selector);
        paymaster.unlockStake();
        vm.expectRevert(GaslessPaymaster.NotOwner.selector);
        paymaster.withdrawStake(payable(alice));
        vm.stopPrank();
    }

    function test_OnlyOwnerCanChangeConfig() public {
        vm.prank(alice);
        vm.expectRevert(GaslessPaymaster.NotOwner.selector);
        paymaster.setAllowed(address(bead), bead.transfer.selector, true);
        vm.prank(alice);
        vm.expectRevert(GaslessPaymaster.NotOwner.selector);
        paymaster.setLimits(1, 1, 1);
    }

    receive() external payable {}
}
