// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TreasuryForwarder} from "./TreasuryForwarder.sol";

/// @title TierStaking
/// @notice Stake-threshold tiers read by Snapshot. Tier 2 stake doubles as the oracle dispute bond.
/// @dev Must be fee-exempt on BeadToken so stakes and unstakes are exact.
contract TierStaking is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant CHAI = 18 ether;
    uint256 public constant CHOTKI = 33 ether;
    uint256 public constant COUNCIL = 99 ether;
    uint256 public constant MAX_COUNCIL_SEATS = 99;
    uint256 public constant DISPUTE_BOND = 33 ether;

    enum Tier {
        NONE,
        CHAI_TIER,
        CHOTKI_TIER,
        COUNCIL_TIER
    }

    IERC20 public immutable BEAD;
    TreasuryForwarder public immutable FORWARDER;
    address public immutable DEPLOYER;

    address public resolver;
    uint256 public councilCount;
    mapping(address => uint256) public stakeOf;
    mapping(address => bool) public bondLocked;

    error ZeroAmount();
    error InsufficientStake();
    error CouncilFull();
    error BondLocked();
    error NotResolver();
    error NotDeployer();
    error ResolverAlreadySet();
    error NotEligibleChallenger();
    error BondNotLocked();

    event Staked(address indexed user, uint256 amount, Tier tier);
    event Unstaked(address indexed user, uint256 amount, Tier tier);
    event BondLockedFor(address indexed user);
    event BondReleased(address indexed user);
    event BondSlashed(address indexed user, uint256 amount);
    event ResolverSet(address indexed resolver);

    constructor(address bead, address forwarder) {
        BEAD = IERC20(bead);
        FORWARDER = TreasuryForwarder(forwarder);
        DEPLOYER = msg.sender;
    }

    function setResolver(address resolver_) external {
        if (msg.sender != DEPLOYER) revert NotDeployer();
        if (resolver != address(0)) revert ResolverAlreadySet();
        resolver = resolver_;
        emit ResolverSet(resolver_);
    }

    function tierOf(address user) public view returns (Tier) {
        return _tierFor(stakeOf[user]);
    }

    function isChotki(address user) public view returns (bool) {
        return stakeOf[user] >= CHOTKI;
    }

    function isCouncil(address user) public view returns (bool) {
        return stakeOf[user] >= COUNCIL;
    }

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 oldStake = stakeOf[msg.sender];
        uint256 newStake = oldStake + amount;
        if (oldStake < COUNCIL && newStake >= COUNCIL) {
            if (councilCount >= MAX_COUNCIL_SEATS) revert CouncilFull();
            ++councilCount;
        }
        stakeOf[msg.sender] = newStake;
        BEAD.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount, _tierFor(newStake));
    }

    function unstake(uint256 amount) external nonReentrant {
        if (bondLocked[msg.sender]) revert BondLocked();
        if (amount == 0) revert ZeroAmount();
        uint256 oldStake = stakeOf[msg.sender];
        if (amount > oldStake) revert InsufficientStake();
        uint256 newStake = oldStake - amount;
        _afterReduce(oldStake, newStake);
        stakeOf[msg.sender] = newStake;
        BEAD.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount, _tierFor(newStake));
    }

    function lockBond(address user) external {
        if (msg.sender != resolver) revert NotResolver();
        if (stakeOf[user] < CHOTKI || bondLocked[user]) revert NotEligibleChallenger();
        bondLocked[user] = true;
        emit BondLockedFor(user);
    }

    function releaseBond(address user) external {
        if (msg.sender != resolver) revert NotResolver();
        if (!bondLocked[user]) revert BondNotLocked();
        bondLocked[user] = false;
        emit BondReleased(user);
    }

    /// @notice Slashed bond goes 100% to the TreasuryForwarder.
    function slashBond(address user) external nonReentrant {
        if (msg.sender != resolver) revert NotResolver();
        if (!bondLocked[user]) revert BondNotLocked();
        bondLocked[user] = false;
        uint256 oldStake = stakeOf[user];
        uint256 newStake = oldStake - DISPUTE_BOND;
        _afterReduce(oldStake, newStake);
        stakeOf[user] = newStake;
        BEAD.safeTransfer(address(FORWARDER), DISPUTE_BOND);
        FORWARDER.forwardTaxes();
        emit BondSlashed(user, DISPUTE_BOND);
    }

    function _afterReduce(uint256 oldStake, uint256 newStake) private {
        if (oldStake >= COUNCIL && newStake < COUNCIL) --councilCount;
    }

    function _tierFor(uint256 amount) private pure returns (Tier) {
        if (amount >= COUNCIL) return Tier.COUNCIL_TIER;
        if (amount >= CHOTKI) return Tier.CHOTKI_TIER;
        if (amount >= CHAI) return Tier.CHAI_TIER;
        return Tier.NONE;
    }
}
