// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BeadToken} from "./BeadToken.sol";
import {TreasuryForwarder} from "./TreasuryForwarder.sol";
import {IFactionToken} from "./interfaces/IFactionToken.sol";
import {Faction, MatchStatus, Outcome} from "./interfaces/PoolTypes.sol";

/// @title EkecheiriaPool
/// @notice Vault + Truce Pool + match state machine. Must be fee-exempt on BeadToken.
contract EkecheiriaPool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MIN_DEPOSIT = 100 ether;
    uint256 public constant PEACE_TAX_BPS = 100;
    uint256 public constant BPS = 10_000;
    uint256 public constant SYMMETRY_BPS = 3000;
    uint256 public constant HOLD_BLOCKS = 50;
    uint256 public constant CHALLENGE_WINDOW = 30 minutes;
    uint256 public constant ORACLE_SILENCE = 48 hours;
    uint256 public constant DISPUTE_TIMEOUT = 7 days;

    struct MatchState {
        uint256 kickoffTime;
        uint256 totalHomeStaked;
        uint256 totalAwayStaked;
        uint256 rewardPool;
        uint256 resolutionTimestamp;
        uint256 disputedAt;
        uint256 maxPoolCapBead;
        MatchStatus status;
        Outcome outcome;
        bool truceAchieved;
        bool rewardReclaimed;
        address homeToken;
        address awayToken;
        address rewardFunder;
    }

    BeadToken public immutable BEAD;
    TreasuryForwarder public immutable FORWARDER;
    address public immutable COUNCIL_EXECUTOR;
    address public immutable DEPLOYER;

    address public matchRegistry;
    address public necklace;
    address public oracleResolver;
    bool public wired;

    mapping(uint256 => MatchState) private _matches;
    mapping(uint256 => mapping(address => Faction)) public userAffiliation;
    mapping(uint256 => mapping(address => uint256)) public depositBlock;
    mapping(uint256 => mapping(Faction => uint256)) public bonusRemaining;

    error NotDeployer();
    error AlreadyWired();
    error ZeroAddress();
    error NotRegistry();
    error NotOracle();
    error NotNecklace();
    error NotCouncilExecutor();
    error MatchNotFound();
    error MatchAlreadyExists();
    error InvalidKickoff();
    error MatchNotOpen();
    error InvalidFaction();
    error InvalidOutcome();
    error AffiliationLocked(Faction chosen);
    error BelowMinimum();
    error PoolCapExceeded();
    error WrongStatus(MatchStatus current);
    error KickoffNotReached();
    error ChallengeWindowActive();
    error ChallengeWindowClosed();
    error FailSafeNotReady();
    error HoldPeriodActive();
    error NothingToClaim();
    error NothingToReclaim();

    event MatchInitialized(uint256 indexed matchId, address homeToken, address awayToken, uint256 kickoffTime);
    event Deposited(uint256 indexed matchId, address indexed user, Faction faction, uint256 net, uint256 tax);
    event EarlyWithdrawal(uint256 indexed matchId, address indexed user, Faction faction, uint256 amount);
    event MatchLocked(uint256 indexed matchId);
    event OutcomeReported(uint256 indexed matchId, Outcome outcome, uint256 timestamp);
    event MatchDisputed(uint256 indexed matchId);
    event MatchSettled(uint256 indexed matchId, Outcome outcome, bool truceAchieved);
    event MatchRefunded(uint256 indexed matchId);
    event SettlementClaimed(uint256 indexed matchId, address indexed user, Faction faction, uint256 principal, uint256 bonus);
    event RefundClaimed(uint256 indexed matchId, address indexed user, Faction faction, uint256 amount);
    event RewardReclaimed(uint256 indexed matchId, address indexed funder, uint256 amount);
    event ForgeBurn(uint256 indexed matchId, uint256 beadBurned);
    event Wired(address registry, address necklace, address resolver);

    modifier onlyRegistry() {
        if (msg.sender != matchRegistry) revert NotRegistry();
        _;
    }

    modifier onlyOracle() {
        if (msg.sender != oracleResolver) revert NotOracle();
        _;
    }

    constructor(address bead, address forwarder, address councilExecutor) {
        if (bead == address(0) || forwarder == address(0) || councilExecutor == address(0)) revert ZeroAddress();
        BEAD = BeadToken(bead);
        FORWARDER = TreasuryForwarder(forwarder);
        COUNCIL_EXECUTOR = councilExecutor;
        DEPLOYER = msg.sender;
    }

    /// @notice One-time wiring that closes the pool/registry/necklace/resolver deploy cycle.
    function wire(address registry_, address necklace_, address resolver_) external {
        if (msg.sender != DEPLOYER) revert NotDeployer();
        if (wired) revert AlreadyWired();
        if (registry_ == address(0) || necklace_ == address(0) || resolver_ == address(0)) revert ZeroAddress();
        wired = true;
        matchRegistry = registry_;
        necklace = necklace_;
        oracleResolver = resolver_;
        emit Wired(registry_, necklace_, resolver_);
    }

    // ---------------------------------------------------------------- registry

    function initializeMatch(
        uint256 matchId,
        address homeToken,
        address awayToken,
        uint256 kickoffTime,
        uint256 maxPoolCapBead,
        uint256 initialReward,
        address rewardFunder
    ) external onlyRegistry {
        MatchState storage m = _matches[matchId];
        if (m.homeToken != address(0)) revert MatchAlreadyExists();
        if (homeToken == address(0) || awayToken == address(0)) revert ZeroAddress();
        if (kickoffTime <= block.timestamp) revert InvalidKickoff();
        m.kickoffTime = kickoffTime;
        m.maxPoolCapBead = maxPoolCapBead;
        m.rewardPool = initialReward;
        m.homeToken = homeToken;
        m.awayToken = awayToken;
        m.rewardFunder = rewardFunder;
        emit MatchInitialized(matchId, homeToken, awayToken, kickoffTime);
    }

    // ----------------------------------------------------------------- deposit

    function deposit(uint256 matchId, Faction faction, uint256 amount) external nonReentrant {
        MatchState storage m = _get(matchId);
        if (m.status != MatchStatus.OPEN || block.timestamp >= m.kickoffTime) revert MatchNotOpen();
        if (faction == Faction.NONE) revert InvalidFaction();
        if (amount < MIN_DEPOSIT) revert BelowMinimum();

        Faction current = userAffiliation[matchId][msg.sender];
        if (current == Faction.NONE) {
            userAffiliation[matchId][msg.sender] = faction;
        } else if (current != faction) {
            revert AffiliationLocked(current);
        }

        uint256 tax = (amount * PEACE_TAX_BPS) / BPS;
        uint256 net = amount - tax;
        if (m.totalHomeStaked + m.totalAwayStaked + net > m.maxPoolCapBead) revert PoolCapExceeded();

        BEAD.transferFrom(msg.sender, address(this), amount);
        BEAD.transfer(address(FORWARDER), tax);
        FORWARDER.forwardTaxes();

        if (faction == Faction.HOME) m.totalHomeStaked += net;
        else m.totalAwayStaked += net;

        depositBlock[matchId][msg.sender] = block.number;
        IFactionToken(_token(m, faction)).mint(msg.sender, net);
        emit Deposited(matchId, msg.sender, faction, net, tax);
    }

    /// @notice Pre-kickoff unwrap, 1:1 on faction tokens (the 1% tax is not returned).
    function withdrawEarly(uint256 matchId, Faction faction, uint256 amount) external nonReentrant {
        MatchState storage m = _get(matchId);
        if (m.status != MatchStatus.OPEN || block.timestamp >= m.kickoffTime) revert MatchNotOpen();
        if (faction == Faction.NONE) revert InvalidFaction();
        if (amount == 0) revert NothingToClaim();

        if (faction == Faction.HOME) m.totalHomeStaked -= amount;
        else m.totalAwayStaked -= amount;

        IFactionToken(_token(m, faction)).burn(msg.sender, amount);
        BEAD.transfer(msg.sender, amount);
        emit EarlyWithdrawal(matchId, msg.sender, faction, amount);
    }

    // ------------------------------------------------------------ state machine

    function lockMatch(uint256 matchId) external {
        MatchState storage m = _get(matchId);
        if (m.status != MatchStatus.OPEN) revert WrongStatus(m.status);
        if (block.timestamp < m.kickoffTime) revert KickoffNotReached();
        m.status = MatchStatus.LOCKED;
        emit MatchLocked(matchId);
    }

    function reportOutcomeProvisional(uint256 matchId, Outcome outcome) external onlyOracle {
        MatchState storage m = _get(matchId);
        if (outcome == Outcome.NONE) revert InvalidOutcome();
        if (m.status == MatchStatus.OPEN) {
            // Only a cancellation may be reported before kickoff.
            if (outcome != Outcome.CANCELLED && block.timestamp < m.kickoffTime) revert KickoffNotReached();
        } else if (m.status != MatchStatus.LOCKED) {
            revert WrongStatus(m.status);
        }
        m.status = MatchStatus.PENDING_RESOLUTION;
        m.outcome = outcome;
        m.resolutionTimestamp = block.timestamp;
        emit OutcomeReported(matchId, outcome, block.timestamp);
    }

    function markDisputed(uint256 matchId) external onlyOracle {
        MatchState storage m = _get(matchId);
        if (m.status != MatchStatus.PENDING_RESOLUTION) revert WrongStatus(m.status);
        if (block.timestamp >= m.resolutionTimestamp + CHALLENGE_WINDOW) revert ChallengeWindowClosed();
        m.status = MatchStatus.DISPUTED;
        m.disputedAt = block.timestamp;
        emit MatchDisputed(matchId);
    }

    function finalizeSettlement(uint256 matchId) external {
        MatchState storage m = _get(matchId);
        if (m.status != MatchStatus.PENDING_RESOLUTION) revert WrongStatus(m.status);
        if (block.timestamp < m.resolutionTimestamp + CHALLENGE_WINDOW) revert ChallengeWindowActive();
        _settle(matchId, m);
    }

    function resolveDispute(uint256 matchId, Outcome finalOutcome) external onlyOracle {
        MatchState storage m = _get(matchId);
        if (m.status != MatchStatus.DISPUTED) revert WrongStatus(m.status);
        if (finalOutcome == Outcome.NONE) revert InvalidOutcome();
        m.outcome = finalOutcome;
        _settle(matchId, m);
    }

    /// @notice Permissionless escape hatch when the oracle goes silent or a dispute never resolves.
    function failSafeRefund(uint256 matchId) external {
        MatchState storage m = _get(matchId);
        if (m.status == MatchStatus.OPEN || m.status == MatchStatus.LOCKED) {
            if (block.timestamp < m.kickoffTime + ORACLE_SILENCE) revert FailSafeNotReady();
        } else if (m.status == MatchStatus.DISPUTED) {
            if (block.timestamp < m.disputedAt + DISPUTE_TIMEOUT) revert FailSafeNotReady();
        } else {
            revert WrongStatus(m.status);
        }
        _refund(matchId, m);
    }

    /// @notice Council circuit breaker for cancelled or delayed fixtures.
    function emergencyRefund(uint256 matchId) external {
        if (msg.sender != COUNCIL_EXECUTOR) revert NotCouncilExecutor();
        MatchState storage m = _get(matchId);
        if (m.status == MatchStatus.SETTLED || m.status == MatchStatus.REFUNDED) revert WrongStatus(m.status);
        _refund(matchId, m);
    }

    // ------------------------------------------------------------------ claims

    function claimSettlement(uint256 matchId, Faction faction) external nonReentrant {
        MatchState storage m = _get(matchId);
        if (m.status != MatchStatus.SETTLED) revert WrongStatus(m.status);
        if (faction == Faction.NONE) revert InvalidFaction();
        if (block.number < depositBlock[matchId][msg.sender] + HOLD_BLOCKS) revert HoldPeriodActive();

        IFactionToken token = IFactionToken(_token(m, faction));
        uint256 bal = token.balanceOf(msg.sender);
        if (bal == 0) revert NothingToClaim();

        // Live supply: shares burned by forging raise the per-token bonus for remaining holders.
        uint256 bonus;
        if (m.truceAchieved) {
            uint256 remaining = bonusRemaining[matchId][faction];
            bonus = (remaining * bal) / token.totalSupply();
            bonusRemaining[matchId][faction] = remaining - bonus;
        }

        token.burn(msg.sender, bal);
        BEAD.transfer(msg.sender, bal + bonus);
        emit SettlementClaimed(matchId, msg.sender, faction, bal, bonus);
    }

    function claimRefund(uint256 matchId, Faction faction) external nonReentrant {
        MatchState storage m = _get(matchId);
        if (m.status != MatchStatus.REFUNDED) revert WrongStatus(m.status);
        if (faction == Faction.NONE) revert InvalidFaction();

        IFactionToken token = IFactionToken(_token(m, faction));
        uint256 bal = token.balanceOf(msg.sender);
        if (bal == 0) revert NothingToClaim();

        token.burn(msg.sender, bal);
        BEAD.transfer(msg.sender, bal);
        emit RefundClaimed(matchId, msg.sender, faction, bal);
    }

    /// @notice Returns the unused reward pool to its funder when no truce paid out.
    function reclaimReward(uint256 matchId) external nonReentrant {
        MatchState storage m = _get(matchId);
        bool eligible = m.status == MatchStatus.REFUNDED || (m.status == MatchStatus.SETTLED && !m.truceAchieved);
        if (!eligible) revert WrongStatus(m.status);
        if (m.rewardReclaimed || m.rewardPool == 0) revert NothingToReclaim();
        m.rewardReclaimed = true;
        uint256 amount = m.rewardPool;
        BEAD.transfer(m.rewardFunder, amount);
        emit RewardReclaimed(matchId, m.rewardFunder, amount);
    }

    // ------------------------------------------------------------------- forge

    /// @notice Called by CosmicNecklace after it burns faction tokens. Burns the matching BEAD principal.
    function onForge(uint256 matchId, uint256 amountPerSide) external {
        if (msg.sender != necklace) revert NotNecklace();
        MatchState storage m = _get(matchId);
        if (m.status != MatchStatus.SETTLED && m.status != MatchStatus.REFUNDED) {
            m.totalHomeStaked -= amountPerSide;
            m.totalAwayStaked -= amountPerSide;
        }
        uint256 burned = amountPerSide * 2;
        BEAD.burn(burned);
        emit ForgeBurn(matchId, burned);
    }

    // ------------------------------------------------------------------- views

    function getMatch(uint256 matchId) external view returns (MatchState memory) {
        return _matches[matchId];
    }

    function matchStatus(uint256 matchId) external view returns (MatchStatus) {
        return _get(matchId).status;
    }

    // ---------------------------------------------------------------- internal

    function _settle(uint256 matchId, MatchState storage m) private {
        if (m.outcome == Outcome.CANCELLED) {
            _refund(matchId, m);
            return;
        }
        m.status = MatchStatus.SETTLED;
        uint256 home = m.totalHomeStaked;
        uint256 away = m.totalAwayStaked;
        uint256 total = home + away;
        uint256 minSide = home < away ? home : away;
        if (total > 0 && minSide * BPS >= SYMMETRY_BPS * total) {
            m.truceAchieved = true;
            uint256 half = m.rewardPool / 2;
            bonusRemaining[matchId][Faction.HOME] = half;
            bonusRemaining[matchId][Faction.AWAY] = half;
        }
        emit MatchSettled(matchId, m.outcome, m.truceAchieved);
    }

    function _refund(uint256 matchId, MatchState storage m) private {
        m.status = MatchStatus.REFUNDED;
        emit MatchRefunded(matchId);
    }

    function _get(uint256 matchId) private view returns (MatchState storage m) {
        m = _matches[matchId];
        if (m.homeToken == address(0)) revert MatchNotFound();
    }

    function _token(MatchState storage m, Faction faction) private view returns (address) {
        return faction == Faction.HOME ? m.homeToken : m.awayToken;
    }
}
