// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Outcome} from "../interfaces/PoolTypes.sol";
import {ReceiverTemplate} from "./cre/ReceiverTemplate.sol";

interface IOutcomeProposer {
    function proposeOutcome(uint256 matchId, Outcome outcome) external;
}

/// @title MatchResultReceiver
/// @notice Chainlink Runtime Environment (CRE) consumer. The keeper emits MatchResolutionRequested; the CRE workflow
/// watches it, reads the result from API-Football, and delivers a signed report through the KeystoneForwarder.
/// The result is handed to the UMA resolver, which opens the 30 minute challenge window.
/// @dev Report payload: abi.encode(uint64 chainSelector, uint256 requestId, uint256 matchId, uint8 outcome) with
/// outcome matching PoolTypes.Outcome (1 home win, 2 away win, 3 draw, 4 cancelled).
contract MatchResultReceiver is ReceiverTemplate {
    IOutcomeProposer public immutable RESOLVER;
    /// @dev CRE chain selector of the chain this contract lives on; rejects reports signed for another chain.
    uint64 public immutable EXPECTED_CHAIN_SELECTOR;

    uint256 public requestCount;
    mapping(uint256 => uint256) public matchOfRequest;
    /// @dev The one request per match whose report is still accepted; consumed on delivery, so a report is single-use.
    mapping(uint256 => uint256) public openRequestOf;

    /// @notice Hot key (keeper) allowed to open requests so the owner can be a multisig.
    address public requester;
    /// @notice Once true it stays true: reports are rejected unless both the expected workflow id and author are set.
    /// @dev The KeystoneForwarder is shared by every CRE workflow, so without identity checks any workflow could report here.
    bool public identityRequired;

    error WrongChain(uint64 received, uint64 expected);
    error StaleOrUnknownRequest(uint256 matchId, uint256 requestId);
    error InvalidOutcomeCode(uint8 code);
    error ZeroAddress();
    error NotRequester();
    error IdentityNotConfigured();

    event MatchResolutionRequested(uint256 indexed matchId, uint256 indexed requestId, string fixtureId);
    event ResultForwarded(uint256 indexed matchId, uint256 indexed requestId, Outcome outcome);
    event RequesterSet(address indexed requester);
    event IdentityRequirementEnabled();

    constructor(address forwarder, address resolver, uint64 expectedChainSelector) ReceiverTemplate(forwarder) {
        if (resolver == address(0)) revert ZeroAddress();
        RESOLVER = IOutcomeProposer(resolver);
        EXPECTED_CHAIN_SELECTOR = expectedChainSelector;
    }

    function setRequester(address requester_) external onlyOwner {
        requester = requester_;
        emit RequesterSet(requester_);
    }

    /// @notice One-way: call after the real workflow is deployed and its id and author are set. Never use with the simulation forwarder.
    function requireWorkflowIdentity() external onlyOwner {
        identityRequired = true;
        emit IdentityRequirementEnabled();
    }

    function onReport(bytes calldata metadata, bytes calldata report) public override {
        if (identityRequired && (getExpectedWorkflowId() == bytes32(0) || getExpectedAuthor() == address(0))) {
            revert IdentityNotConfigured();
        }
        super.onReport(metadata, report);
    }

    /// @notice Starts a lookup. A new request for the same match supersedes any earlier open one.
    /// @param fixtureId API-Football fixture id, read by the workflow from the event data.
    function requestMatchResult(uint256 matchId, string calldata fixtureId) external returns (uint256 requestId) {
        if (msg.sender != owner() && msg.sender != requester) revert NotRequester();
        requestId = ++requestCount;
        matchOfRequest[requestId] = matchId;
        openRequestOf[matchId] = requestId;
        emit MatchResolutionRequested(matchId, requestId, fixtureId);
    }

    /// @dev A revert here (for example the match is not locked yet) leaves the request open so delivery can be retried.
    function _processReport(bytes calldata report) internal override {
        (uint64 chainSelector, uint256 requestId, uint256 matchId, uint8 code) =
            abi.decode(report, (uint64, uint256, uint256, uint8));

        if (chainSelector != EXPECTED_CHAIN_SELECTOR) revert WrongChain(chainSelector, EXPECTED_CHAIN_SELECTOR);
        if (requestId == 0 || openRequestOf[matchId] != requestId || matchOfRequest[requestId] != matchId) {
            revert StaleOrUnknownRequest(matchId, requestId);
        }
        if (code == 0 || code > uint8(Outcome.CANCELLED)) revert InvalidOutcomeCode(code);

        delete openRequestOf[matchId];
        RESOLVER.proposeOutcome(matchId, Outcome(code));
        emit ResultForwarded(matchId, requestId, Outcome(code));
    }
}
