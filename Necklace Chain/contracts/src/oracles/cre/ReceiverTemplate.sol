// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IReceiver} from "./IReceiver.sol";

/// @title ReceiverTemplate
/// @notice Base for CRE report consumers: only the configured forwarder may call, with optional workflow identity checks.
/// @dev Do not set the identity checks while using the simulation MockForwarder; it supplies no workflow metadata.
abstract contract ReceiverTemplate is IReceiver, Ownable {
    address private _forwarder;
    address private _expectedAuthor;
    bytes10 private _expectedWorkflowName;
    bytes32 private _expectedWorkflowId;

    error InvalidForwarderAddress();
    error InvalidSender(address sender, address expected);
    error InvalidAuthor(address received, address expected);
    error InvalidWorkflowName(bytes10 received, bytes10 expected);
    error InvalidWorkflowId(bytes32 received, bytes32 expected);
    error WorkflowNameRequiresAuthorValidation();
    error MetadataTooShort();

    event ForwarderAddressUpdated(address indexed previousForwarder, address indexed newForwarder);
    event ExpectedAuthorUpdated(address indexed previousAuthor, address indexed newAuthor);
    event ExpectedWorkflowNameUpdated(bytes10 indexed previousName, bytes10 indexed newName);
    event ExpectedWorkflowIdUpdated(bytes32 indexed previousId, bytes32 indexed newId);

    constructor(address forwarder_) Ownable(msg.sender) {
        if (forwarder_ == address(0)) revert InvalidForwarderAddress();
        _forwarder = forwarder_;
        emit ForwarderAddressUpdated(address(0), forwarder_);
    }

    function getForwarderAddress() external view returns (address) {
        return _forwarder;
    }

    function getExpectedAuthor() public view returns (address) {
        return _expectedAuthor;
    }

    function getExpectedWorkflowName() external view returns (bytes10) {
        return _expectedWorkflowName;
    }

    function getExpectedWorkflowId() public view returns (bytes32) {
        return _expectedWorkflowId;
    }

    function onReport(bytes calldata metadata, bytes calldata report) public virtual {
        if (msg.sender != _forwarder) revert InvalidSender(msg.sender, _forwarder);

        if (_expectedWorkflowId != bytes32(0) || _expectedAuthor != address(0) || _expectedWorkflowName != bytes10(0)) {
            (bytes32 workflowId, bytes10 workflowName, address workflowOwner) = _decodeMetadata(metadata);
            if (_expectedWorkflowId != bytes32(0) && workflowId != _expectedWorkflowId) {
                revert InvalidWorkflowId(workflowId, _expectedWorkflowId);
            }
            if (_expectedAuthor != address(0) && workflowOwner != _expectedAuthor) {
                revert InvalidAuthor(workflowOwner, _expectedAuthor);
            }
            if (_expectedWorkflowName != bytes10(0)) {
                // Names are 40-bit truncated hashes, so they are only meaningful together with the owner.
                if (_expectedAuthor == address(0)) revert WorkflowNameRequiresAuthorValidation();
                if (workflowName != _expectedWorkflowName) revert InvalidWorkflowName(workflowName, _expectedWorkflowName);
            }
        }

        _processReport(report);
    }

    /// @dev Setting the forwarder to address(0) is rejected: it would let anyone call onReport.
    function setForwarderAddress(address forwarder_) external onlyOwner {
        if (forwarder_ == address(0)) revert InvalidForwarderAddress();
        emit ForwarderAddressUpdated(_forwarder, forwarder_);
        _forwarder = forwarder_;
    }

    function setExpectedAuthor(address author) external onlyOwner {
        emit ExpectedAuthorUpdated(_expectedAuthor, author);
        _expectedAuthor = author;
    }

    function setExpectedWorkflowId(bytes32 id) external onlyOwner {
        emit ExpectedWorkflowIdUpdated(_expectedWorkflowId, id);
        _expectedWorkflowId = id;
    }

    /// @notice Pass the plaintext workflow name; it is encoded like the CRE engine does (sha256, hex, first 10 characters).
    function setExpectedWorkflowName(string calldata name) external onlyOwner {
        bytes10 previous = _expectedWorkflowName;
        if (bytes(name).length == 0) {
            _expectedWorkflowName = bytes10(0);
        } else {
            bytes32 hash = sha256(bytes(name));
            bytes memory first10 = new bytes(10);
            bytes16 hexChars = "0123456789abcdef";
            for (uint256 i; i < 5; ++i) {
                first10[i * 2] = hexChars[uint8(hash[i]) >> 4];
                first10[i * 2 + 1] = hexChars[uint8(hash[i]) & 0x0f];
            }
            _expectedWorkflowName = bytes10(first10);
        }
        emit ExpectedWorkflowNameUpdated(previous, _expectedWorkflowName);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function _decodeMetadata(bytes calldata metadata)
        internal
        pure
        returns (bytes32 workflowId, bytes10 workflowName, address workflowOwner)
    {
        // Production delivery is 64 bytes (the last 2 are the report id); simulation-style 62 bytes also works.
        if (metadata.length < 62) revert MetadataTooShort();
        workflowId = bytes32(metadata[0:32]);
        workflowName = bytes10(metadata[32:42]);
        workflowOwner = address(bytes20(metadata[42:62]));
    }

    function _processReport(bytes calldata report) internal virtual;
}
