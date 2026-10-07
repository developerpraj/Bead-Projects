import { parseAbi } from "viem";

export const FACTION = { NONE: 0, HOME: 1, AWAY: 2 } as const;
export const STATUS = ["OPEN", "LOCKED", "PENDING_RESOLUTION", "SETTLED", "REFUNDED", "DISPUTED"] as const;

export const beadAbi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
]);

export const factionTokenAbi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
]);

export const poolAbi = parseAbi([
  "struct MatchState { uint256 kickoffTime; uint256 totalHomeStaked; uint256 totalAwayStaked; uint256 rewardPool; uint256 resolutionTimestamp; uint256 disputedAt; uint256 maxPoolCapBead; uint8 status; uint8 outcome; bool truceAchieved; bool rewardReclaimed; address homeToken; address awayToken; address rewardFunder; }",
  "function getMatch(uint256 matchId) view returns (MatchState)",
  "function userAffiliation(uint256 matchId, address user) view returns (uint8)",
  "function deposit(uint256 matchId, uint8 faction, uint256 amount)",
  "function withdrawEarly(uint256 matchId, uint8 faction, uint256 amount)",
  "function claimSettlement(uint256 matchId, uint8 faction)",
  "function claimRefund(uint256 matchId, uint8 faction)",
]);

export const necklaceAbi = parseAbi([
  "function forgeDiplomaticNecklace(uint256 matchId) returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function ownerOf(uint256 tokenId) view returns (address)",
  "function getTenureCycles(uint256 tokenId) view returns (uint256)",
  "function getVotingWeight(uint256 tokenId) view returns (uint256)",
  "function getFeeDiscountBps(uint256 tokenId) view returns (uint256)",
  "function getRank(uint256 tokenId) view returns (string)",
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
]);

export const stakingAbi = parseAbi([
  "function stakeOf(address) view returns (uint256)",
  "function tierOf(address) view returns (uint8)",
  "function councilCount() view returns (uint256)",
  "function bondLocked(address) view returns (bool)",
  "function stake(uint256 amount)",
  "function unstake(uint256 amount)",
]);
