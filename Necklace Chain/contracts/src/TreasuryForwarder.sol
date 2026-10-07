// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TreasuryForwarder
/// @notice Immutable, zero-discretion pass-through. Sweeps its entire $BEAD balance to the public-goods recipient.
contract TreasuryForwarder {
    using SafeERC20 for IERC20;

    IERC20 public immutable BEAD_TOKEN;
    address public immutable PUBLIC_GOODS_EOA;

    error ZeroAddress();

    event TaxForwarded(address indexed recipient, uint256 amount);

    constructor(address beadToken, address publicGoodsEoa) {
        if (beadToken == address(0) || publicGoodsEoa == address(0)) revert ZeroAddress();
        BEAD_TOKEN = IERC20(beadToken);
        PUBLIC_GOODS_EOA = publicGoodsEoa;
    }

    /// @notice Callable by anyone; no admin, no other destination.
    function forwardTaxes() external {
        uint256 bal = BEAD_TOKEN.balanceOf(address(this));
        if (bal == 0) return;
        BEAD_TOKEN.safeTransfer(PUBLIC_GOODS_EOA, bal);
        emit TaxForwarded(PUBLIC_GOODS_EOA, bal);
    }
}
