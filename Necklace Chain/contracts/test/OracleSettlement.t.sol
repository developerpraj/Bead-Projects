// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EkecheiriaPool} from "../src/EkecheiriaPool.sol";
import {TierStaking} from "../src/TierStaking.sol";
import {UMAOptimisticResolver} from "../src/oracles/UMAOptimisticResolver.sol";
import {MatchResultReceiver} from "../src/oracles/MatchResultReceiver.sol";
import {ReceiverTemplate} from "../src/oracles/cre/ReceiverTemplate.sol";
import {IReceiver} from "../src/oracles/cre/IReceiver.sol";
import {Faction, MatchStatus, Outcome} from "../src/interfaces/PoolTypes.sol";
import {NecklaceBase} from "./NecklaceBase.sol";
import {MockOptimisticOracleV3, MockERC20} from "./mocks/MockOptimisticOracleV3.sol";
import {MockKeystoneForwarder} from "./mocks/MockKeystoneForwarder.sol";

contract OracleSettlementTest is NecklaceBase {
    uint256 internal constant BOND = 100 ether;
    uint64 internal constant CHAIN_SELECTOR = 10_344_971_235_874_465_080;

    MockOptimisticOracleV3 internal oo;
    MockERC20 internal bondToken;
    MockKeystoneForwarder internal forwarder_;
    UMAOptimisticResolver internal resolver;
    MatchResultReceiver internal receiver;

    function _makeOracle() internal override returns (address) {
        oo = new MockOptimisticOracleV3();
        bondToken = new MockERC20();
        forwarder_ = new MockKeystoneForwarder();
        resolver = new UMAOptimisticResolver(address(oo), address(pool), address(staking), address(bondToken), BOND);
        receiver = new MatchResultReceiver(address(forwarder_), address(resolver), CHAIN_SELECTOR);
        resolver.setConsumer(address(receiver));
        staking.setResolver(address(resolver));
        bondToken.mint(address(resolver), 10 * BOND);
        return address(resolver);
    }

    function _lockedMatchWithDeposits() internal {
        _deposit(alice, Faction.HOME, 1_000 ether);
        _deposit(bob, Faction.AWAY, 1_000 ether);
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
    }

    function _request() internal returns (uint256 requestId) {
        requestId = receiver.requestMatchResult(MATCH_ID, "fixture-123");
    }

    function _reportPayload(uint64 selector, uint256 requestId, uint256 matchId, uint8 code)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(selector, requestId, matchId, code);
    }

    /// @dev Requests a result and has the (mock) forwarder deliver it, like the CRE workflow would.
    function _report(uint256 code) internal returns (uint256 requestId) {
        requestId = _request();
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, requestId, MATCH_ID, uint8(code)));
    }

    function _makeChotki(address user) internal {
        vm.startPrank(user);
        bead.approve(address(staking), 33 ether);
        staking.stake(33 ether);
        vm.stopPrank();
        bondToken.mint(user, BOND);
        vm.prank(user);
        bondToken.approve(address(resolver), BOND);
    }

    // ------------------------------------------------------------ CRE receiver

    function test_RequestEmitsEventForTheWorkflowTrigger() public {
        vm.expectEmit(true, true, false, true, address(receiver));
        emit MatchResultReceiver.MatchResolutionRequested(MATCH_ID, 1, "fixture-123");
        assertEq(_request(), 1);
        assertEq(receiver.openRequestOf(MATCH_ID), 1);
    }

    function test_OnlyOwnerCanRequest() public {
        vm.prank(alice);
        vm.expectRevert();
        receiver.requestMatchResult(MATCH_ID, "x");
    }

    function test_OnlyTheForwarderCanDeliver() public {
        _lockedMatchWithDeposits();
        uint256 id = _request();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ReceiverTemplate.InvalidSender.selector, alice, address(forwarder_))
        );
        receiver.onReport("", _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 3));
    }

    function test_DonResultOpensChallengeWindow() public {
        _lockedMatchWithDeposits();
        _report(uint256(Outcome.DRAW));

        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.PENDING_RESOLUTION));
        assertTrue(resolver.assertionOf(MATCH_ID) != bytes32(0));

        vm.expectRevert(EkecheiriaPool.ChallengeWindowActive.selector);
        pool.finalizeSettlement(MATCH_ID);

        skip(30 minutes);
        oo.settleAssertion(resolver.assertionOf(MATCH_ID));
        pool.finalizeSettlement(MATCH_ID);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.SETTLED));
    }

    function test_CancellationReportRefundsAfterTheWindow() public {
        _lockedMatchWithDeposits();
        _report(uint256(Outcome.CANCELLED));
        skip(30 minutes);
        pool.finalizeSettlement(MATCH_ID);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.REFUNDED));
    }

    function test_ReportIsSingleUse() public {
        _lockedMatchWithDeposits();
        uint256 id = _report(uint256(Outcome.DRAW));
        vm.expectRevert(abi.encodeWithSelector(MatchResultReceiver.StaleOrUnknownRequest.selector, MATCH_ID, id));
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 3));
    }

    function test_NewRequestSupersedesTheOldOne() public {
        _lockedMatchWithDeposits();
        uint256 oldId = _request();
        uint256 newId = _request();
        vm.expectRevert(abi.encodeWithSelector(MatchResultReceiver.StaleOrUnknownRequest.selector, MATCH_ID, oldId));
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, oldId, MATCH_ID, 3));
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, newId, MATCH_ID, 3));
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.PENDING_RESOLUTION));
    }

    function test_ReportForAnotherChainIsRejected() public {
        _lockedMatchWithDeposits();
        uint256 id = _request();
        vm.expectRevert(abi.encodeWithSelector(MatchResultReceiver.WrongChain.selector, uint64(1), CHAIN_SELECTOR));
        forwarder_.deliver(address(receiver), "", _reportPayload(1, id, MATCH_ID, 3));
    }

    function test_UnknownMatchOrRequestIsRejected() public {
        _lockedMatchWithDeposits();
        uint256 id = _request();
        vm.expectRevert(abi.encodeWithSelector(MatchResultReceiver.StaleOrUnknownRequest.selector, 2, id));
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, id, 2, 3));
        vm.expectRevert(abi.encodeWithSelector(MatchResultReceiver.StaleOrUnknownRequest.selector, MATCH_ID, 0));
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, 0, MATCH_ID, 3));
    }

    function test_OutOfRangeOutcomeCodesAreRejected() public {
        _lockedMatchWithDeposits();
        uint256 id = _request();
        vm.expectRevert(abi.encodeWithSelector(MatchResultReceiver.InvalidOutcomeCode.selector, uint8(0)));
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 0));
        vm.expectRevert(abi.encodeWithSelector(MatchResultReceiver.InvalidOutcomeCode.selector, uint8(5)));
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 5));
    }

    function test_DeliveryBeforeLockRevertsAndStaysRetryable() public {
        // Open match, non-cancel result: the pool refuses, the request must stay open.
        uint256 id = _request();
        vm.expectRevert(EkecheiriaPool.KickoffNotReached.selector);
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 3));
        assertEq(receiver.openRequestOf(MATCH_ID), id);

        _deposit(alice, Faction.HOME, 1_000 ether);
        vm.warp(kickoff);
        pool.lockMatch(MATCH_ID);
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 3));
        assertEq(receiver.openRequestOf(MATCH_ID), 0);
    }

    function test_WorkflowIdAndAuthorChecksUseTheMetadata() public {
        _lockedMatchWithDeposits();
        bytes32 wfId = keccak256("workflow");
        address wfOwner = makeAddr("workflowOwner");
        receiver.setExpectedWorkflowId(wfId);
        receiver.setExpectedAuthor(wfOwner);
        uint256 id = _request();
        bytes memory report = _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 3);

        // 64 bytes like production: id | name | owner | reportId
        bytes memory good = abi.encodePacked(wfId, bytes10("0123456789"), wfOwner, bytes2(0));
        bytes memory wrongId = abi.encodePacked(bytes32(uint256(1)), bytes10("0123456789"), wfOwner, bytes2(0));
        bytes memory wrongOwner = abi.encodePacked(wfId, bytes10("0123456789"), alice, bytes2(0));

        vm.expectRevert(abi.encodeWithSelector(ReceiverTemplate.InvalidWorkflowId.selector, bytes32(uint256(1)), wfId));
        forwarder_.deliver(address(receiver), wrongId, report);
        vm.expectRevert(abi.encodeWithSelector(ReceiverTemplate.InvalidAuthor.selector, alice, wfOwner));
        forwarder_.deliver(address(receiver), wrongOwner, report);
        vm.expectRevert(ReceiverTemplate.MetadataTooShort.selector);
        forwarder_.deliver(address(receiver), hex"0102", report);

        forwarder_.deliver(address(receiver), good, report);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.PENDING_RESOLUTION));
    }

    function test_RequesterRoleLetsAKeeperRequestWhileOwnerStaysInControl() public {
        address keeper = makeAddr("keeper");
        vm.prank(keeper);
        vm.expectRevert(MatchResultReceiver.NotRequester.selector);
        receiver.requestMatchResult(MATCH_ID, "x");

        receiver.setRequester(keeper);
        vm.prank(keeper);
        assertEq(receiver.requestMatchResult(MATCH_ID, "x"), 1);

        vm.prank(keeper);
        vm.expectRevert();
        receiver.setRequester(alice);

        receiver.setRequester(address(0));
        vm.prank(keeper);
        vm.expectRevert(MatchResultReceiver.NotRequester.selector);
        receiver.requestMatchResult(MATCH_ID, "x");
    }

    function test_RequiredIdentityRejectsReportsUntilIdAndAuthorAreSet() public {
        _lockedMatchWithDeposits();
        uint256 id = _request();
        bytes memory report = _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 3);

        receiver.requireWorkflowIdentity();
        assertTrue(receiver.identityRequired());

        // Nothing set: any workflow on the shared forwarder would otherwise get through.
        vm.expectRevert(MatchResultReceiver.IdentityNotConfigured.selector);
        forwarder_.deliver(address(receiver), "", report);

        bytes32 wfId = keccak256("workflow");
        address wfOwner = makeAddr("workflowOwner");
        receiver.setExpectedWorkflowId(wfId);
        vm.expectRevert(MatchResultReceiver.IdentityNotConfigured.selector);
        forwarder_.deliver(address(receiver), abi.encodePacked(wfId, bytes10(0), wfOwner, bytes2(0)), report);

        receiver.setExpectedAuthor(wfOwner);
        forwarder_.deliver(address(receiver), abi.encodePacked(wfId, bytes10(0), wfOwner, bytes2(0)), report);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.PENDING_RESOLUTION));
    }

    function test_ClearingTheIdentityAfterRequiringItFailsClosed() public {
        _lockedMatchWithDeposits();
        receiver.setExpectedWorkflowId(keccak256("workflow"));
        receiver.setExpectedAuthor(address(0xA11CE));
        receiver.requireWorkflowIdentity();
        uint256 id = _request();

        receiver.setExpectedWorkflowId(bytes32(0));
        vm.expectRevert(MatchResultReceiver.IdentityNotConfigured.selector);
        forwarder_.deliver(address(receiver), "", _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 3));
    }

    function test_RequireIdentityIsOwnerOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        receiver.requireWorkflowIdentity();
    }

    function test_WorkflowNameNeedsAnAuthorAndMatchesTheEngineEncoding() public {
        _lockedMatchWithDeposits();
        receiver.setExpectedWorkflowName("my_workflow");
        // sha256("my_workflow") starts with b76f3ae1de..., encoded as the ASCII of its first 10 hex characters.
        assertEq(receiver.getExpectedWorkflowName(), bytes10(0x62373666336165316465));

        uint256 id = _request();
        bytes memory report = _reportPayload(CHAIN_SELECTOR, id, MATCH_ID, 3);
        bytes memory md = abi.encodePacked(bytes32(0), bytes10(0x62373666336165316465), address(0), bytes2(0));
        vm.expectRevert(ReceiverTemplate.WorkflowNameRequiresAuthorValidation.selector);
        forwarder_.deliver(address(receiver), md, report);

        receiver.setExpectedAuthor(address(0xA11CE));
        bytes memory wrongName = abi.encodePacked(bytes32(0), bytes10("0123456789"), address(0xA11CE), bytes2(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                ReceiverTemplate.InvalidWorkflowName.selector, bytes10("0123456789"), bytes10(0x62373666336165316465)
            )
        );
        forwarder_.deliver(address(receiver), wrongName, report);
        bytes memory right = abi.encodePacked(bytes32(0), bytes10(0x62373666336165316465), address(0xA11CE), bytes2(0));
        forwarder_.deliver(address(receiver), right, report);
    }

    function test_ForwarderCannotBeUnset() public {
        vm.expectRevert(ReceiverTemplate.InvalidForwarderAddress.selector);
        receiver.setForwarderAddress(address(0));
        receiver.setForwarderAddress(address(0xF00D));
        assertEq(receiver.getForwarderAddress(), address(0xF00D));
        vm.expectRevert(ReceiverTemplate.InvalidForwarderAddress.selector);
        new MatchResultReceiver(address(0), address(resolver), CHAIN_SELECTOR);
        vm.expectRevert(MatchResultReceiver.ZeroAddress.selector);
        new MatchResultReceiver(address(forwarder_), address(0), CHAIN_SELECTOR);
    }

    function test_AdminSettersAreOwnerOnly() public {
        vm.startPrank(alice);
        vm.expectRevert();
        receiver.setForwarderAddress(address(1));
        vm.expectRevert();
        receiver.setExpectedAuthor(address(1));
        vm.expectRevert();
        receiver.setExpectedWorkflowId(bytes32(uint256(1)));
        vm.expectRevert();
        receiver.setExpectedWorkflowName("x");
        vm.stopPrank();
    }

    function test_SupportsTheReceiverInterface() public view {
        assertTrue(receiver.supportsInterface(type(IReceiver).interfaceId));
        assertTrue(receiver.supportsInterface(0x01ffc9a7)); // ERC165
        assertFalse(receiver.supportsInterface(0xffffffff));
    }

    function test_OnlyConsumerCanPropose() public {
        _lockedMatchWithDeposits();
        vm.expectRevert(UMAOptimisticResolver.NotConsumer.selector);
        resolver.proposeOutcome(MATCH_ID, Outcome.DRAW);
    }

    // ----------------------------------------------------------- UMA challenges

    function test_UpheldChallengeRefundsMatchAndReleasesBond() public {
        _lockedMatchWithDeposits();
        _report(uint256(Outcome.HOME_WIN));
        _makeChotki(carol);

        vm.prank(carol);
        resolver.challengeOracleResult(MATCH_ID);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.DISPUTED));
        assertTrue(staking.bondLocked(carol));

        oo.resolveDisputed(resolver.assertionOf(MATCH_ID), false);
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.REFUNDED));
        assertFalse(staking.bondLocked(carol));
        assertEq(staking.stakeOf(carol), 33 ether);
    }

    function test_RejectedChallengeSlashesBondToPublicGoods() public {
        _lockedMatchWithDeposits();
        _report(uint256(Outcome.HOME_WIN));
        _makeChotki(carol);

        vm.prank(carol);
        resolver.challengeOracleResult(MATCH_ID);

        uint256 pgBefore = bead.balanceOf(PUBLIC_GOODS);
        oo.resolveDisputed(resolver.assertionOf(MATCH_ID), true);

        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.SETTLED));
        assertEq(bead.balanceOf(PUBLIC_GOODS) - pgBefore, 33 ether);
        assertEq(staking.stakeOf(carol), 0);
    }

    function test_BondStillResolvesAfterCouncilRefundedTheMatch() public {
        _lockedMatchWithDeposits();
        _report(uint256(Outcome.HOME_WIN));
        _makeChotki(carol);
        vm.prank(carol);
        resolver.challengeOracleResult(MATCH_ID);

        vm.prank(council);
        pool.emergencyRefund(MATCH_ID);

        uint256 pgBefore = bead.balanceOf(PUBLIC_GOODS);
        oo.resolveDisputed(resolver.assertionOf(MATCH_ID), true);

        // The pool call fails quietly, but the frivolous challenger is still slashed and unlocked.
        assertEq(bead.balanceOf(PUBLIC_GOODS) - pgBefore, 33 ether);
        assertFalse(staking.bondLocked(carol));
        assertEq(uint8(pool.matchStatus(MATCH_ID)), uint8(MatchStatus.REFUNDED));
    }

    function test_NonChotkiCannotChallenge() public {
        _lockedMatchWithDeposits();
        _report(uint256(Outcome.HOME_WIN));
        bondToken.mint(carol, BOND);
        vm.startPrank(carol);
        bondToken.approve(address(resolver), BOND);
        vm.expectRevert(TierStaking.NotEligibleChallenger.selector);
        resolver.challengeOracleResult(MATCH_ID);
        vm.stopPrank();
    }

    function test_ChallengeAfterWindowReverts() public {
        _lockedMatchWithDeposits();
        _report(uint256(Outcome.HOME_WIN));
        _makeChotki(carol);

        skip(30 minutes);
        vm.prank(carol);
        vm.expectRevert(EkecheiriaPool.ChallengeWindowClosed.selector);
        resolver.challengeOracleResult(MATCH_ID);
    }

    function test_SecondChallengeReverts() public {
        _lockedMatchWithDeposits();
        _report(uint256(Outcome.HOME_WIN));
        _makeChotki(carol);
        _makeChotki(bob);

        vm.prank(carol);
        resolver.challengeOracleResult(MATCH_ID);
        vm.prank(bob);
        vm.expectRevert(UMAOptimisticResolver.AlreadyChallenged.selector);
        resolver.challengeOracleResult(MATCH_ID);
    }
}
