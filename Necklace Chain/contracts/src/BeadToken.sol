// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title BeadToken ($BEAD)
/// @notice 13.8B hard-capped ERC-20 with a 1% Peace Tax on non-exempt transfers.
contract BeadToken is ERC20Capped, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 13_800_000_000 ether;
    uint256 public constant PEACE_TAX_BPS = 100; // 1%
    uint256 public constant DUST_THRESHOLD = 100 ether; // 100 whole tokens

    address public treasuryForwarder;
    mapping(address => bool) public feeExempt;

    error DustTransfer();
    error ForwarderAlreadySet();
    error ZeroAddress();

    event FeeExemptSet(address indexed account, bool exempt);
    event TreasuryForwarderSet(address indexed forwarder);

    /// @param owner_ Admin for the fee-exempt list and one-time forwarder wiring (renounce after setup).
    /// @param recipients [ecosystem, treasury, teamVesting, liquidity, seedVesting]
    constructor(address owner_, address[5] memory recipients)
        ERC20("Necklace Chain", "BEAD")
        ERC20Capped(MAX_SUPPLY)
        Ownable(owner_)
    {
        for (uint256 i; i < 5; ++i) {
            if (recipients[i] == address(0)) revert ZeroAddress();
        }
        _mint(recipients[0], (MAX_SUPPLY * 40) / 100); // Ecosystem
        _mint(recipients[1], (MAX_SUPPLY * 20) / 100); // Treasury
        _mint(recipients[2], (MAX_SUPPLY * 15) / 100); // Team (12-mo cliff vesting)
        _mint(recipients[3], (MAX_SUPPLY * 15) / 100); // DEX liquidity
        _mint(recipients[4], (MAX_SUPPLY * 10) / 100); // Seed (6-mo cliff vesting)
    }

    /// @notice One-time wiring of the TreasuryForwarder (breaks token<->forwarder constructor cycle).
    function setTreasuryForwarder(address forwarder) external onlyOwner {
        if (treasuryForwarder != address(0)) revert ForwarderAlreadySet();
        if (forwarder == address(0)) revert ZeroAddress();
        treasuryForwarder = forwarder;
        feeExempt[forwarder] = true;
        emit TreasuryForwarderSet(forwarder);
        emit FeeExemptSet(forwarder, true);
    }

    function setFeeExempt(address account, bool exempt) external onlyOwner {
        feeExempt[account] = exempt;
        emit FeeExemptSet(account, exempt);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        if (from == address(0) || to == address(0) || feeExempt[from] || feeExempt[to]) {
            super._update(from, to, value);
            return;
        }
        if (value < DUST_THRESHOLD) revert DustTransfer();
        uint256 fee = (value * PEACE_TAX_BPS) / 10_000;
        super._update(from, treasuryForwarder, fee);
        super._update(from, to, value - fee);
    }
}
