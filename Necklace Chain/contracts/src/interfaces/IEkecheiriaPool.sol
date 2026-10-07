// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MatchStatus, Outcome} from "./PoolTypes.sol";

interface IEkecheiriaPool {
    function initializeMatch(
        uint256 matchId,
        address homeToken,
        address awayToken,
        uint256 kickoffTime,
        uint256 maxPoolCapBead,
        uint256 initialReward,
        address rewardFunder
    ) external;

    function onForge(uint256 matchId, uint256 amountPerSide) external;
    function reportOutcomeProvisional(uint256 matchId, Outcome outcome) external;
    function markDisputed(uint256 matchId) external;
    function resolveDispute(uint256 matchId, Outcome finalOutcome) external;
    function necklace() external view returns (address);
    function matchStatus(uint256 matchId) external view returns (MatchStatus);
}
