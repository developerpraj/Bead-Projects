import { keccak256, parseAbi, toBytes } from "viem";

/** Event emitted by MatchResultReceiver.requestMatchResult; the workflow's EVM log trigger watches it. */
export const requestedEventAbi = parseAbi([
  "event MatchResolutionRequested(uint256 indexed matchId, uint256 indexed requestId, string fixtureId)",
]);

export const requestedEventTopic = keccak256(toBytes("MatchResolutionRequested(uint256,uint256,string)"));

/** Report payload decoded by MatchResultReceiver._processReport. */
export const REPORT_PARAMETERS = "uint64 chainSelector, uint256 requestId, uint256 matchId, uint8 outcome";
