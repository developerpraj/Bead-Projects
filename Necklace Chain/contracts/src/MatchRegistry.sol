// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IEkecheiriaPool} from "./interfaces/IEkecheiriaPool.sol";
import {IFactionToken} from "./interfaces/IFactionToken.sol";
import {IMatchRegistry} from "./interfaces/IMatchRegistry.sol";
import {MatchStatus} from "./interfaces/PoolTypes.sol";

/// @title MatchRegistry
/// @notice Singleton hub. Clones a FactionToken pair per match and initializes the pool.
contract MatchRegistry is IMatchRegistry {
    using SafeERC20 for IERC20;

    IEkecheiriaPool public immutable POOL;
    IERC20 public immutable BEAD;
    address public immutable FACTION_IMPLEMENTATION;
    address public immutable COUNCIL_EXECUTOR;
    address public immutable DEPLOYER;

    bool public bootstrapActive = true;

    mapping(uint256 => address) private _homeToken;
    mapping(uint256 => address) private _awayToken;

    error NotAuthorized();
    error MatchExists();
    error ZeroAddress();
    error NotDeployer();
    error BootstrapAlreadyRenounced();

    event MatchCreated(uint256 indexed matchId, address homeToken, address awayToken, uint256 kickoffTime);
    event BootstrapRenounced(address indexed councilExecutor);

    constructor(address pool, address bead, address factionImplementation, address councilExecutor) {
        if (
            pool == address(0) || bead == address(0) || factionImplementation == address(0)
                || councilExecutor == address(0)
        ) revert ZeroAddress();
        POOL = IEkecheiriaPool(pool);
        BEAD = IERC20(bead);
        FACTION_IMPLEMENTATION = factionImplementation;
        COUNCIL_EXECUTOR = councilExecutor;
        DEPLOYER = msg.sender;
    }

    /// @notice Hands match creation to the Council Executor for good.
    function renounceBootstrap() external {
        if (msg.sender != DEPLOYER) revert NotDeployer();
        if (!bootstrapActive) revert BootstrapAlreadyRenounced();
        bootstrapActive = false;
        emit BootstrapRenounced(COUNCIL_EXECUTOR);
    }

    /// @dev Caller must have approved this registry for `initialReward` BEAD; the reward funds the pool atomically.
    function createMatch(
        uint256 matchId,
        uint256 kickoffTime,
        string calldata homeName,
        string calldata awayName,
        uint256 maxPoolCapBead,
        uint256 initialReward
    ) external returns (address homeToken, address awayToken) {
        if (msg.sender != COUNCIL_EXECUTOR && !(bootstrapActive && msg.sender == DEPLOYER)) revert NotAuthorized();
        if (_homeToken[matchId] != address(0)) revert MatchExists();

        address necklace = POOL.necklace();
        string memory id = Strings.toString(matchId);

        homeToken = Clones.clone(FACTION_IMPLEMENTATION);
        awayToken = Clones.clone(FACTION_IMPLEMENTATION);
        IFactionToken(homeToken).initialize(homeName, string.concat("TRUCE-", id, "H"), address(POOL), necklace);
        IFactionToken(awayToken).initialize(awayName, string.concat("TRUCE-", id, "A"), address(POOL), necklace);

        _homeToken[matchId] = homeToken;
        _awayToken[matchId] = awayToken;

        if (initialReward > 0) BEAD.safeTransferFrom(msg.sender, address(POOL), initialReward);
        POOL.initializeMatch(matchId, homeToken, awayToken, kickoffTime, maxPoolCapBead, initialReward, msg.sender);

        emit MatchCreated(matchId, homeToken, awayToken, kickoffTime);
    }

    function getMatchTokens(uint256 matchId) external view returns (address, address) {
        return (_homeToken[matchId], _awayToken[matchId]);
    }

    function isMatchActive(uint256 matchId) external view returns (bool) {
        if (_homeToken[matchId] == address(0)) return false;
        MatchStatus s = POOL.matchStatus(matchId);
        return s != MatchStatus.SETTLED && s != MatchStatus.REFUNDED;
    }
}
