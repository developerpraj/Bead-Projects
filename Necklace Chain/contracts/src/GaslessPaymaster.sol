// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEntryPointV06, UserOperation, PostOpMode} from "./interfaces/IEntryPointV06.sol";

/// @title GaslessPaymaster
/// @notice ERC-4337 v0.6 paymaster that sponsors only whitelisted (target, selector) calls from Coinbase Smart Wallets.
/// @dev Must be staked in the EntryPoint (addStake) because validation reads this contract's own storage.
/// Funded in ETH via the genesis gas float or any later top-up; there is no on-chain BEAD-to-ETH conversion.
contract GaslessPaymaster {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    bytes4 private constant EXECUTE = bytes4(keccak256("execute(address,uint256,bytes)"));
    bytes4 private constant EXECUTE_BATCH = bytes4(keccak256("executeBatch((address,uint256,bytes)[])"));
    uint256 public constant MAX_BATCH = 5;

    IEntryPointV06 public immutable ENTRY_POINT;
    address public immutable OWNER;
    address public immutable WALLET_FACTORY;

    uint256 public maxCostPerOp;
    uint256 public senderDailyBudget;
    uint256 public globalDailyBudget;

    mapping(address => mapping(bytes4 => bool)) public allowed;
    mapping(uint256 => uint256) public globalSpent;
    mapping(uint256 => mapping(address => uint256)) public senderSpent;

    error NotEntryPoint();
    error NotOwner();
    error NotSponsored(address target, bytes4 selector);
    error ValueNotAllowed();
    error BadCallData();
    error BatchTooLarge();
    error UnknownFactory();
    error CostTooHigh();
    error SenderBudgetExceeded();
    error GlobalBudgetExceeded();
    error TransferFailed();

    event AllowedSet(address indexed target, bytes4 indexed selector, bool allowed);
    event LimitsSet(uint256 maxCostPerOp, uint256 senderDailyBudget, uint256 globalDailyBudget);

    modifier onlyEntryPoint() {
        if (msg.sender != address(ENTRY_POINT)) revert NotEntryPoint();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert NotOwner();
        _;
    }

    constructor(
        address entryPoint,
        address walletFactory,
        uint256 maxCostPerOp_,
        uint256 senderDailyBudget_,
        uint256 globalDailyBudget_
    ) {
        ENTRY_POINT = IEntryPointV06(entryPoint);
        WALLET_FACTORY = walletFactory;
        OWNER = msg.sender;
        _setLimits(maxCostPerOp_, senderDailyBudget_, globalDailyBudget_);
    }

    receive() external payable {
        ENTRY_POINT.depositTo{value: msg.value}(address(this));
    }

    // ------------------------------------------------------------- ERC-4337

    function validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 maxCost)
        external
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        if (userOp.initCode.length != 0) {
            if (userOp.initCode.length < 20 || address(bytes20(userOp.initCode[:20])) != WALLET_FACTORY) {
                revert UnknownFactory();
            }
        }
        _checkCallData(userOp.callData);

        if (maxCost > maxCostPerOp) revert CostTooHigh();
        uint256 day = block.timestamp / 1 days;
        uint256 newSender = senderSpent[day][userOp.sender] + maxCost;
        uint256 newGlobal = globalSpent[day] + maxCost;
        if (newSender > senderDailyBudget) revert SenderBudgetExceeded();
        if (newGlobal > globalDailyBudget) revert GlobalBudgetExceeded();
        senderSpent[day][userOp.sender] = newSender;
        globalSpent[day] = newGlobal;

        context = abi.encode(userOp.sender, day, maxCost);
        validationData = 0;
    }

    /// @dev Refunds the unused part of the budget reserved at validation.
    function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) external onlyEntryPoint {
        (address sender, uint256 day, uint256 reserved) = abi.decode(context, (address, uint256, uint256));
        if (actualGasCost < reserved) {
            uint256 unused = reserved - actualGasCost;
            senderSpent[day][sender] -= unused;
            globalSpent[day] -= unused;
        }
    }

    // ---------------------------------------------------------------- admin

    function setAllowed(address target, bytes4 selector, bool isAllowed) external onlyOwner {
        allowed[target][selector] = isAllowed;
        emit AllowedSet(target, selector, isAllowed);
    }

    function setLimits(uint256 maxCostPerOp_, uint256 senderDailyBudget_, uint256 globalDailyBudget_)
        external
        onlyOwner
    {
        _setLimits(maxCostPerOp_, senderDailyBudget_, globalDailyBudget_);
    }

    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        ENTRY_POINT.addStake{value: msg.value}(unstakeDelaySec);
    }

    function unlockStake() external onlyOwner {
        ENTRY_POINT.unlockStake();
    }

    function withdrawStake(address payable to) external onlyOwner {
        ENTRY_POINT.withdrawStake(to);
    }

    function withdrawTo(address payable to, uint256 amount) external onlyOwner {
        ENTRY_POINT.withdrawTo(to, amount);
    }

    // ------------------------------------------------------------- internal

    function _setLimits(uint256 a, uint256 b, uint256 c) private {
        maxCostPerOp = a;
        senderDailyBudget = b;
        globalDailyBudget = c;
        emit LimitsSet(a, b, c);
    }

    function _checkCallData(bytes calldata callData) private view {
        if (callData.length < 4) revert BadCallData();
        bytes4 selector = bytes4(callData[:4]);
        if (selector == EXECUTE) {
            (address dest, uint256 value, bytes memory data) = abi.decode(callData[4:], (address, uint256, bytes));
            _checkOne(dest, value, data);
        } else if (selector == EXECUTE_BATCH) {
            Call[] memory calls = abi.decode(callData[4:], (Call[]));
            if (calls.length == 0 || calls.length > MAX_BATCH) revert BatchTooLarge();
            for (uint256 i; i < calls.length; ++i) {
                _checkOne(calls[i].target, calls[i].value, calls[i].data);
            }
        } else {
            revert BadCallData();
        }
    }

    function _checkOne(address target, uint256 value, bytes memory data) private view {
        if (value != 0) revert ValueNotAllowed();
        if (data.length < 4) revert BadCallData();
        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }
        if (!allowed[target][selector]) revert NotSponsored(target, selector);
    }
}
