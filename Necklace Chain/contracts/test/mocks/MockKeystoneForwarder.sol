// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IReceiverLike {
    function onReport(bytes calldata metadata, bytes calldata report) external;
}

/// @dev Stand-in for the KeystoneForwarder: it is the only caller the receiver accepts.
contract MockKeystoneForwarder {
    function deliver(address receiver, bytes calldata metadata, bytes calldata report) external {
        IReceiverLike(receiver).onReport(metadata, report);
    }
}
