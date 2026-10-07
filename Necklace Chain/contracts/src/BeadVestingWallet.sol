// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {VestingWalletCliff} from "@openzeppelin/contracts/finance/VestingWalletCliff.sol";

/// @notice Linear vesting with a cliff, used for the team and private-seed BEAD allocations.
contract BeadVestingWallet is VestingWallet, VestingWalletCliff {
    constructor(address beneficiary, uint64 startTimestamp, uint64 durationSeconds, uint64 cliffSeconds)
        VestingWallet(beneficiary, startTimestamp, durationSeconds)
        VestingWalletCliff(cliffSeconds)
    {}

    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp)
        internal
        view
        override(VestingWallet, VestingWalletCliff)
        returns (uint256)
    {
        return super._vestingSchedule(totalAllocation, timestamp);
    }
}
