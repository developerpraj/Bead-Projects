// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMatchRegistry {
    function getMatchTokens(uint256 matchId) external view returns (address homeToken, address awayToken);
    function isMatchActive(uint256 matchId) external view returns (bool);
}
