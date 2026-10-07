// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Interface the Chainlink KeystoneForwarder calls to deliver a CRE report.
interface IReceiver is IERC165 {
    /// @param metadata Workflow identity: workflowId (32) | workflowName (10) | workflowOwner (20) | reportId (2, production only).
    /// @param report ABI-encoded payload produced by the workflow.
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
