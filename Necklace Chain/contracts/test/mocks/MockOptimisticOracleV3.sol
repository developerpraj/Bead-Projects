// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOptimisticOracleV3} from "../../src/interfaces/IOptimisticOracleV3.sol";

interface IAssertionCallbacks {
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external;
    function assertionDisputedCallback(bytes32 assertionId) external;
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Bond", "MBOND") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Mimics the OOv3 pieces the resolver uses; DVM votes are simulated through `resolveDisputed`.
contract MockOptimisticOracleV3 is IOptimisticOracleV3 {
    struct Assertion {
        address callback;
        IERC20 currency;
        uint256 bond;
        uint256 expiry;
        bool disputed;
        bool settled;
    }

    uint256 public minBond = 10 ether;
    uint256 private _counter;
    mapping(bytes32 => Assertion) public assertions;

    function assertTruth(
        bytes memory,
        address,
        address callbackRecipient,
        address,
        uint64 liveness,
        IERC20 currency,
        uint256 bond,
        bytes32,
        bytes32
    ) external returns (bytes32 id) {
        id = bytes32(++_counter);
        currency.transferFrom(msg.sender, address(this), bond);
        assertions[id] = Assertion(callbackRecipient, currency, bond, block.timestamp + liveness, false, false);
    }

    function disputeAssertion(bytes32 id, address) external {
        Assertion storage a = assertions[id];
        a.currency.transferFrom(msg.sender, address(this), a.bond);
        a.disputed = true;
        IAssertionCallbacks(a.callback).assertionDisputedCallback(id);
    }

    function settleAssertion(bytes32 id) external {
        Assertion storage a = assertions[id];
        require(!a.disputed && !a.settled && block.timestamp >= a.expiry, "not settleable");
        a.settled = true;
        IAssertionCallbacks(a.callback).assertionResolvedCallback(id, true);
    }

    function resolveDisputed(bytes32 id, bool assertedTruthfully) external {
        Assertion storage a = assertions[id];
        require(a.disputed && !a.settled, "not disputed");
        a.settled = true;
        IAssertionCallbacks(a.callback).assertionResolvedCallback(id, assertedTruthfully);
    }

    function getMinimumBond(address) external view returns (uint256) {
        return minBond;
    }

    function defaultIdentifier() external pure returns (bytes32) {
        return bytes32("ASSERT_TRUTH");
    }
}
