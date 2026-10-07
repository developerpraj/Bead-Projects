// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title FactionToken
/// @notice Per-match faction receipt token, deployed as an EIP-1167 clone. Minted 1:1 by the pool on deposit.
contract FactionToken is Initializable, ERC20Upgradeable {
    address public pool;
    address public necklace;

    error Unauthorized();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address pool_, address necklace_)
        external
        initializer
    {
        __ERC20_init(name_, symbol_);
        pool = pool_;
        necklace = necklace_;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != pool) revert Unauthorized();
        _mint(to, amount);
    }

    /// @dev Privileged burn: pool (settlement/refund) or necklace (forge). No allowance needed.
    function burn(address from, uint256 amount) external {
        if (msg.sender != pool && msg.sender != necklace) revert Unauthorized();
        _burn(from, amount);
    }
}
