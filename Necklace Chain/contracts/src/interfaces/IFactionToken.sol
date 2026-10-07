// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFactionToken is IERC20 {
    function initialize(string memory name_, string memory symbol_, address pool_, address necklace_) external;
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}
