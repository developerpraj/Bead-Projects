// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IOptimisticOracleV3} from "../interfaces/IOptimisticOracleV3.sol";
import {IEkecheiriaPool} from "../interfaces/IEkecheiriaPool.sol";
import {Outcome} from "../interfaces/PoolTypes.sol";
import {TierStaking} from "../TierStaking.sol";

/// @title UMAOptimisticResolver
/// @notice Posts the Chainlink-reported result as a bonded OOv3 assertion with a 30 minute challenge window.
/// Tier-2 (Chotki) stakers may challenge; a rejected challenge slashes their 33 BEAD bond to the TreasuryForwarder.
/// @dev Must be funded with `bondAmount` of `bondCurrency` per assertion (the asserter bond lives in this contract).
contract UMAOptimisticResolver {
    using SafeERC20 for IERC20;

    uint64 public constant LIVENESS = 30 minutes;

    IOptimisticOracleV3 public immutable ORACLE;
    IEkecheiriaPool public immutable POOL;
    TierStaking public immutable STAKING;
    IERC20 public immutable BOND_CURRENCY;
    uint256 public immutable BOND_AMOUNT;
    address public immutable DEPLOYER;

    address public consumer;

    mapping(uint256 => bytes32) public assertionOf;
    mapping(bytes32 => uint256) public matchOfAssertion;
    mapping(uint256 => Outcome) public proposedOutcome;
    mapping(uint256 => address) public challengerOf;

    error NotConsumer();
    error NotOracle();
    error NotDeployer();
    error ConsumerAlreadySet();
    error AlreadyAsserted();
    error NotAsserted();
    error AlreadyChallenged();
    error BondTooLow();

    event ConsumerSet(address indexed consumer);
    event OutcomeAsserted(uint256 indexed matchId, bytes32 indexed assertionId, Outcome outcome);
    event OutcomeChallenged(uint256 indexed matchId, address indexed challenger);
    event ChallengeUpheld(uint256 indexed matchId, address indexed challenger);
    event ChallengeRejected(uint256 indexed matchId, address indexed challenger);

    constructor(address oracle, address pool, address staking, address bondCurrency, uint256 bondAmount) {
        ORACLE = IOptimisticOracleV3(oracle);
        POOL = IEkecheiriaPool(pool);
        STAKING = TierStaking(staking);
        BOND_CURRENCY = IERC20(bondCurrency);
        BOND_AMOUNT = bondAmount;
        DEPLOYER = msg.sender;
        if (bondAmount < IOptimisticOracleV3(oracle).getMinimumBond(bondCurrency)) revert BondTooLow();
    }

    function setConsumer(address consumer_) external {
        if (msg.sender != DEPLOYER) revert NotDeployer();
        if (consumer != address(0)) revert ConsumerAlreadySet();
        consumer = consumer_;
        emit ConsumerSet(consumer_);
    }

    /// @notice Called by SportsFunctionConsumer with the DON result.
    function proposeOutcome(uint256 matchId, Outcome outcome) external {
        if (msg.sender != consumer) revert NotConsumer();
        if (assertionOf[matchId] != bytes32(0)) revert AlreadyAsserted();

        POOL.reportOutcomeProvisional(matchId, outcome);

        bytes memory claim = abi.encodePacked(
            "Necklace Chain match ", Strings.toString(matchId), " resolved with outcome code ", Strings.toString(uint8(outcome))
        );
        BOND_CURRENCY.forceApprove(address(ORACLE), BOND_AMOUNT);
        bytes32 id = ORACLE.assertTruth(
            claim,
            address(this),
            address(this),
            address(0),
            LIVENESS,
            BOND_CURRENCY,
            BOND_AMOUNT,
            ORACLE.defaultIdentifier(),
            bytes32(0)
        );
        assertionOf[matchId] = id;
        matchOfAssertion[id] = matchId;
        proposedOutcome[matchId] = outcome;
        emit OutcomeAsserted(matchId, id, outcome);
    }

    /// @notice Tier-2 challenge. Challenger posts the OOv3 bond currency; their Chotki stake is locked as a slash target.
    function challengeOracleResult(uint256 matchId) external {
        bytes32 id = assertionOf[matchId];
        if (id == bytes32(0)) revert NotAsserted();
        if (challengerOf[matchId] != address(0)) revert AlreadyChallenged();

        STAKING.lockBond(msg.sender);
        challengerOf[matchId] = msg.sender;

        BOND_CURRENCY.safeTransferFrom(msg.sender, address(this), BOND_AMOUNT);
        BOND_CURRENCY.forceApprove(address(ORACLE), BOND_AMOUNT);
        ORACLE.disputeAssertion(id, msg.sender);
        emit OutcomeChallenged(matchId, msg.sender);
    }

    function assertionDisputedCallback(bytes32 assertionId) external {
        if (msg.sender != address(ORACLE)) revert NotOracle();
        POOL.markDisputed(matchOfAssertion[assertionId]);
    }

    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external {
        if (msg.sender != address(ORACLE)) revert NotOracle();
        uint256 matchId = matchOfAssertion[assertionId];
        address challenger = challengerOf[matchId];
        if (challenger == address(0)) return; // Undisputed: pool.finalizeSettlement is permissionless.

        if (assertedTruthfully) {
            STAKING.slashBond(challenger);
            emit ChallengeRejected(matchId, challenger);
            // The pool may already be refunded (council breaker or fail-safe); the bond outcome must still apply.
            try POOL.resolveDispute(matchId, proposedOutcome[matchId]) {} catch {}
        } else {
            STAKING.releaseBond(challenger);
            emit ChallengeUpheld(matchId, challenger);
            // The reported result was wrong and the true result is unknown: refund everyone.
            try POOL.resolveDispute(matchId, Outcome.CANCELLED) {} catch {}
        }
    }

    /// @notice Moves bond-currency float (returned bonds and dispute winnings) out of the resolver.
    function withdrawBondCurrency(address to, uint256 amount) external {
        if (msg.sender != DEPLOYER) revert NotDeployer();
        BOND_CURRENCY.safeTransfer(to, amount);
    }
}
