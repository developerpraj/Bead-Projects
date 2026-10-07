// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployV1Base} from "../script/DeployV1Base.s.sol";
import {GaslessPaymaster} from "../src/GaslessPaymaster.sol";
import {MatchResultReceiver} from "../src/oracles/MatchResultReceiver.sol";
import {VestingWalletCliff} from "@openzeppelin/contracts/finance/VestingWalletCliff.sol";
import {MockEntryPointV06} from "./GaslessPaymaster.t.sol";
import {MockOptimisticOracleV3, MockERC20} from "./mocks/MockOptimisticOracleV3.sol";
import {MockKeystoneForwarder} from "./mocks/MockKeystoneForwarder.sol";

/// @dev vm.setEnv is process-wide and Foundry runs tests in parallel, so every env-dependent scenario lives in one test.
contract DeployScriptTest is Test {
    // Default local deployer key used by the script on chain 31337 (anvil account 0).
    address internal constant LOCAL_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function test_ScriptWiresPaymasterAndOracles() public {
        _paymasterWithoutOracles();
        _paymasterAndOracles();
        _vestingWalletsAndRenounce();
    }

    function _vestingWalletsAndRenounce() internal {
        MockEntryPointV06 ep = new MockEntryPointV06();
        vm.setEnv("ENTRY_POINT", vm.toString(address(ep)));
        vm.setEnv("UMA_OOV3", vm.toString(address(0)));
        address team = address(0x7EA);
        address seed = address(0x5EED);
        vm.setEnv("TEAM_BENEFICIARY", vm.toString(team));
        vm.setEnv("SEED_BENEFICIARY", vm.toString(seed));
        vm.setEnv("RENOUNCE_BEAD_OWNERSHIP", "true");
        vm.deal(LOCAL_DEPLOYER, 1 ether);

        DeployV1Base.Deployed memory d = new DeployV1Base().run();

        uint256 cap = d.bead.cap();
        assertEq(d.bead.balanceOf(d.teamVesting), (cap * 15) / 100);
        assertEq(d.bead.balanceOf(d.seedVesting), (cap * 10) / 100);
        assertEq(VestingWalletCliff(payable(d.teamVesting)).owner(), team);
        assertEq(VestingWalletCliff(payable(d.seedVesting)).owner(), seed);
        assertEq(VestingWalletCliff(payable(d.teamVesting)).cliff() - VestingWalletCliff(payable(d.teamVesting)).start(), 365 days);
        assertEq(VestingWalletCliff(payable(d.seedVesting)).cliff() - VestingWalletCliff(payable(d.seedVesting)).start(), 180 days);
        assertTrue(d.bead.feeExempt(d.teamVesting));
        assertEq(d.bead.owner(), address(0));

        // Nothing is releasable before the cliff.
        assertEq(VestingWalletCliff(payable(d.teamVesting)).releasable(address(d.bead)), 0);
    }

    function _paymasterWithoutOracles() internal {
        MockEntryPointV06 ep = new MockEntryPointV06();
        vm.setEnv("ENTRY_POINT", vm.toString(address(ep)));
        vm.setEnv("SMART_WALLET_FACTORY", vm.toString(address(0xFAC7)));
        vm.setEnv("UMA_OOV3", vm.toString(address(0)));
        vm.deal(LOCAL_DEPLOYER, 1 ether);

        DeployV1Base.Deployed memory d = new DeployV1Base().run();

        assertTrue(d.paymaster != address(0));
        assertEq(d.consumer, address(0));
        assertEq(ep.balanceOf(d.paymaster), 0.04 ether);
        assertEq(ep.stake(), 0.01 ether);
        assertEq(ep.unstakeDelay(), 1 days);
        assertEq(GaslessPaymaster(payable(d.paymaster)).OWNER(), LOCAL_DEPLOYER);
        assertTrue(GaslessPaymaster(payable(d.paymaster)).allowed(address(d.pool), d.pool.deposit.selector));
    }

    function _paymasterAndOracles() internal {
        MockEntryPointV06 ep = new MockEntryPointV06();
        MockOptimisticOracleV3 oo = new MockOptimisticOracleV3();
        MockERC20 bondToken = new MockERC20();
        MockKeystoneForwarder crForwarder = new MockKeystoneForwarder();
        vm.setEnv("ENTRY_POINT", vm.toString(address(ep)));
        vm.setEnv("UMA_OOV3", vm.toString(address(oo)));
        vm.setEnv("BOND_CURRENCY", vm.toString(address(bondToken)));
        vm.setEnv("BOND_AMOUNT", "100000000000000000000");
        vm.setEnv("CRE_FORWARDER", vm.toString(address(crForwarder)));
        vm.setEnv("CRE_CHAIN_SELECTOR", "10344971235874465080");
        vm.setEnv("CRE_WORKFLOW_ID", "0x0000000000000000000000000000000000000000000000000000000000000abc");
        vm.setEnv("CRE_WORKFLOW_OWNER", vm.toString(address(0xBEEF1)));
        vm.setEnv("CRE_KEEPER", vm.toString(address(0xBEEF2)));
        vm.setEnv("TRANSFER_RECEIVER_OWNERSHIP", "true");
        vm.setEnv("COUNCIL_EXECUTOR", vm.toString(address(0xC0C0)));
        vm.deal(LOCAL_DEPLOYER, 1 ether);

        DeployV1Base.Deployed memory d = new DeployV1Base().run();

        MatchResultReceiver receiver = MatchResultReceiver(d.consumer);
        assertEq(receiver.getForwarderAddress(), address(crForwarder));
        assertEq(receiver.EXPECTED_CHAIN_SELECTOR(), 10_344_971_235_874_465_080);
        assertEq(receiver.getExpectedWorkflowId(), bytes32(uint256(0xabc)));
        assertEq(receiver.getExpectedAuthor(), address(0xBEEF1));
        assertTrue(receiver.identityRequired());
        assertEq(receiver.requester(), address(0xBEEF2));
        assertEq(receiver.owner(), address(0xC0C0));
        assertEq(address(receiver.RESOLVER()), d.resolver);
        assertEq(d.pool.oracleResolver(), d.resolver);
        assertEq(d.staking.resolver(), d.resolver);
    }
}
