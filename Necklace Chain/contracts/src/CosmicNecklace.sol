// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IEkecheiriaPool} from "./interfaces/IEkecheiriaPool.sol";
import {IFactionToken} from "./interfaces/IFactionToken.sol";
import {IMatchRegistry} from "./interfaces/IMatchRegistry.sol";

/// @title CosmicNecklace (Rama Node)
/// @notice Forged by burning 54 Home + 54 Away faction tokens of one match. Utilities are non-monetary only.
contract CosmicNecklace is ERC721, ReentrancyGuard {
    uint256 public constant BEADS_PER_FACTION = 54 ether;
    uint256 public constant CYCLE_DURATION = 108 days;
    uint256 public constant MAX_BOOST_CYCLES = 5;

    struct NecklaceLineage {
        uint256 matchId;
        uint256 forgedAt;
    }

    IMatchRegistry public immutable MATCH_REGISTRY;
    IEkecheiriaPool public immutable POOL;

    uint256 private _nextTokenId = 1;
    mapping(uint256 => uint256) public lastTransferTimestamp;
    mapping(uint256 => NecklaceLineage) public necklaceLineage;

    error InvalidMatch();

    event NecklaceForged(address indexed forger, uint256 indexed tokenId, uint256 indexed matchId);
    event HoldingReset(uint256 indexed tokenId, address indexed from, address indexed to);

    constructor(address registry, address pool) ERC721("Cosmic Necklace", "RAMA") {
        MATCH_REGISTRY = IMatchRegistry(registry);
        POOL = IEkecheiriaPool(pool);
    }

    function forgeDiplomaticNecklace(uint256 matchId) external nonReentrant returns (uint256 tokenId) {
        (address homeToken, address awayToken) = MATCH_REGISTRY.getMatchTokens(matchId);
        if (homeToken == address(0)) revert InvalidMatch();

        IFactionToken(homeToken).burn(msg.sender, BEADS_PER_FACTION);
        IFactionToken(awayToken).burn(msg.sender, BEADS_PER_FACTION);
        POOL.onForge(matchId, BEADS_PER_FACTION);

        tokenId = _nextTokenId++;
        necklaceLineage[tokenId] = NecklaceLineage(matchId, block.timestamp);
        _safeMint(msg.sender, tokenId);
        emit NecklaceForged(msg.sender, tokenId, matchId);
    }

    function getTenureCycles(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);
        return (block.timestamp - lastTransferTimestamp[tokenId]) / CYCLE_DURATION;
    }

    function getVotingWeight(uint256 tokenId) external view returns (uint256) {
        uint256 cycles = getTenureCycles(tokenId);
        if (cycles > MAX_BOOST_CYCLES) cycles = MAX_BOOST_CYCLES;
        return 1 + cycles;
    }

    function getFeeDiscountBps(uint256 tokenId) external view returns (uint256) {
        uint256 cycles = getTenureCycles(tokenId);
        if (cycles >= 3) return 3000;
        if (cycles >= 1) return 1500;
        return 0;
    }

    function getRank(uint256 tokenId) external view returns (string memory) {
        uint256 cycles = getTenureCycles(tokenId);
        if (cycles >= 3) return "Galactic";
        if (cycles == 2) return "Solar";
        if (cycles == 1) return "Ascendant";
        return "Initiate";
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = super._update(to, tokenId, auth);
        lastTransferTimestamp[tokenId] = block.timestamp;
        if (from != address(0)) emit HoldingReset(tokenId, from, to);
    }
}
