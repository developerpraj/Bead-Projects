// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {BeadToken} from "../src/BeadToken.sol";
import {TreasuryForwarder} from "../src/TreasuryForwarder.sol";
import {FactionToken} from "../src/FactionToken.sol";
import {EkecheiriaPool} from "../src/EkecheiriaPool.sol";
import {MatchRegistry} from "../src/MatchRegistry.sol";
import {CosmicNecklace} from "../src/CosmicNecklace.sol";
import {TierStaking} from "../src/TierStaking.sol";
import {BeadVestingWallet} from "../src/BeadVestingWallet.sol";
import {GaslessPaymaster} from "../src/GaslessPaymaster.sol";
import {IEntryPointV06} from "../src/interfaces/IEntryPointV06.sol";
import {UMAOptimisticResolver} from "../src/oracles/UMAOptimisticResolver.sol";
import {MatchResultReceiver} from "../src/oracles/MatchResultReceiver.sol";

/// @notice V1 deployment. Env vars supply every address; local defaults are anvil accounts and Protocol Guild.
/// Oracle contracts are deployed only when UMA_OOV3 is set (leave unset for local rehearsal).
contract DeployV1Base is Script {
    // Protocol Guild Base vesting contract, per their donation docs.
    address internal constant PROTOCOL_GUILD_BASE = 0xffaaCCFe120f3fC47f42102cF4F28e837cd49A20;
    // Canonical ERC-4337 EntryPoint v0.6 (same address on every chain).
    address internal constant ENTRY_POINT_V06 = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;

    struct Deployed {
        BeadToken bead;
        TreasuryForwarder forwarder;
        EkecheiriaPool pool;
        MatchRegistry registry;
        CosmicNecklace necklace;
        TierStaking staking;
        address resolver;
        address consumer;
        address paymaster;
        address teamVesting;
        address seedVesting;
    }

    function _defaultEntryPoint() private view returns (address) {
        return (block.chainid == 8453 || block.chainid == 84532) ? ENTRY_POINT_V06 : address(0);
    }

    /// @dev Reads <PREFIX>_BENEFICIARY, <PREFIX>_VESTING_CLIFF and <PREFIX>_VESTING_DURATION (seconds) from the environment.
    function _vestingOrDefault(string memory prefix, address fallbackAddr, uint256 defaultCliff, uint256 defaultDuration)
        private
        returns (address)
    {
        address beneficiary = vm.envOr(string.concat(prefix, "_BENEFICIARY"), address(0));
        if (beneficiary == address(0)) return fallbackAddr;
        uint256 cliff = vm.envOr(string.concat(prefix, "_VESTING_CLIFF"), defaultCliff);
        uint256 duration = vm.envOr(string.concat(prefix, "_VESTING_DURATION"), defaultDuration);
        address wallet = address(new BeadVestingWallet(beneficiary, uint64(block.timestamp), uint64(duration), uint64(cliff)));
        console2.log(string.concat(prefix, " vesting wallet"), wallet);
        return wallet;
    }

    function run() external returns (Deployed memory d) {
        // Signing: PRIVATE_KEY, or a Foundry keystore (`--account <name> --sender <address>`) so no raw key is needed.
        // The well-known anvil key is a local-only fallback.
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        if (pk == 0 && block.chainid == 31337) {
            pk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        }
        address deployer;
        if (pk != 0) {
            deployer = vm.addr(pk);
        } else {
            deployer = msg.sender;
            require(deployer != DEFAULT_SENDER, "pass --sender with --account, or set PRIVATE_KEY");
        }

        address[5] memory genesis = [
            vm.envOr("ECOSYSTEM_ADDR", address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8)),
            vm.envOr("TREASURY_ADDR", address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC)),
            vm.envOr("TEAM_VESTING_ADDR", address(0x90F79bf6EB2c4f870365E785982E1f101E93b906)),
            vm.envOr("LIQUIDITY_ADDR", address(0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65)),
            vm.envOr("SEED_VESTING_ADDR", address(0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc))
        ];
        address publicGoods = vm.envOr("PUBLIC_GOODS_EOA", PROTOCOL_GUILD_BASE);
        address councilExecutor = vm.envOr("COUNCIL_EXECUTOR", deployer);

        vm.startBroadcast(pk);

        // Team and seed tokens are vested by cliff wallets when a beneficiary is given; otherwise the *_VESTING_ADDR is used as is.
        genesis[2] = _vestingOrDefault("TEAM", genesis[2], 365 days, 4 * 365 days);
        genesis[4] = _vestingOrDefault("SEED", genesis[4], 180 days, 2 * 365 days);
        d.teamVesting = genesis[2];
        d.seedVesting = genesis[4];

        d.bead = new BeadToken(deployer, genesis);
        d.forwarder = new TreasuryForwarder(address(d.bead), publicGoods);
        d.bead.setTreasuryForwarder(address(d.forwarder));

        d.pool = new EkecheiriaPool(address(d.bead), address(d.forwarder), councilExecutor);
        FactionToken factionImpl = new FactionToken();
        d.registry = new MatchRegistry(address(d.pool), address(d.bead), address(factionImpl), councilExecutor);
        d.necklace = new CosmicNecklace(address(d.registry), address(d.pool));
        d.staking = new TierStaking(address(d.bead), address(d.forwarder));

        address uma = vm.envOr("UMA_OOV3", address(0));
        if (uma == address(0)) {
            d.resolver = deployer;
            console2.log("UMA_OOV3 unset: deployer acts as oracle (local rehearsal only)");
        } else {
            UMAOptimisticResolver resolver = new UMAOptimisticResolver(
                uma,
                address(d.pool),
                address(d.staking),
                vm.envAddress("BOND_CURRENCY"),
                vm.envUint("BOND_AMOUNT")
            );
            // The CRE KeystoneForwarder (or MockForwarder while simulating) is the only address allowed to deliver reports.
            MatchResultReceiver receiver = new MatchResultReceiver(
                vm.envAddress("CRE_FORWARDER"), address(resolver), uint64(vm.envUint("CRE_CHAIN_SELECTOR"))
            );
            // Identity checks need metadata the simulation forwarder does not provide: set these only for the deployed workflow.
            bytes32 workflowId = vm.envOr("CRE_WORKFLOW_ID", bytes32(0));
            address workflowOwner = vm.envOr("CRE_WORKFLOW_OWNER", address(0));
            if (workflowId != bytes32(0)) receiver.setExpectedWorkflowId(workflowId);
            if (workflowOwner != address(0)) receiver.setExpectedAuthor(workflowOwner);
            if (workflowId != bytes32(0) && workflowOwner != address(0)) {
                // The KeystoneForwarder is shared by all workflows: from here on only this workflow may report.
                receiver.requireWorkflowIdentity();
            } else {
                console2.log("WARNING: workflow id/owner unset. Before using the real forwarder call setExpectedWorkflowId,");
                console2.log("setExpectedAuthor, then requireWorkflowIdentity on the receiver.");
            }
            address keeper = vm.envOr("CRE_KEEPER", address(0));
            if (keeper != address(0)) receiver.setRequester(keeper);
            if (vm.envOr("TRANSFER_RECEIVER_OWNERSHIP", false)) receiver.transferOwnership(councilExecutor);
            resolver.setConsumer(address(receiver));
            d.resolver = address(resolver);
            d.consumer = address(receiver);
            d.staking.setResolver(address(resolver));
        }

        d.pool.wire(address(d.registry), address(d.necklace), d.resolver);

        d.bead.setFeeExempt(address(d.pool), true);
        d.bead.setFeeExempt(address(d.staking), true);
        d.bead.setFeeExempt(genesis[2], true);
        d.bead.setFeeExempt(genesis[4], true);

        // Sprint 2: deployed when an EntryPoint v0.6 is known (canonical address on Base and Base Sepolia).
        address entryPoint = vm.envOr("ENTRY_POINT", _defaultEntryPoint());
        if (entryPoint != address(0)) {
            GaslessPaymaster pm = new GaslessPaymaster(
                entryPoint,
                vm.envAddress("SMART_WALLET_FACTORY"),
                vm.envOr("PAYMASTER_MAX_COST_PER_OP", uint256(0.0002 ether)),
                vm.envOr("PAYMASTER_SENDER_DAILY", uint256(0.001 ether)),
                vm.envOr("PAYMASTER_GLOBAL_DAILY", uint256(0.01 ether))
            );
            pm.setAllowed(address(d.bead), d.bead.approve.selector, true);
            pm.setAllowed(address(d.pool), d.pool.deposit.selector, true);
            pm.setAllowed(address(d.pool), d.pool.withdrawEarly.selector, true);
            pm.setAllowed(address(d.pool), d.pool.claimSettlement.selector, true);
            pm.setAllowed(address(d.pool), d.pool.claimRefund.selector, true);
            pm.setAllowed(address(d.necklace), d.necklace.forgeDiplomaticNecklace.selector, true);
            pm.setAllowed(address(d.staking), d.staking.stake.selector, true);
            pm.setAllowed(address(d.staking), d.staking.unstake.selector, true);
            uint256 gasFloat = vm.envOr("GENESIS_GAS_FLOAT", uint256(0.04 ether));
            uint256 repStake = vm.envOr("PAYMASTER_STAKE", uint256(0.01 ether));
            uint32 unstakeDelay = uint32(vm.envOr("PAYMASTER_UNSTAKE_DELAY", uint256(1 days)));
            // Deposit pays for UserOps; stake is locked collateral that lets validation read our storage.
            IEntryPointV06(entryPoint).depositTo{value: gasFloat}(address(pm));
            pm.addStake{value: repStake}(unstakeDelay);
            d.paymaster = address(pm);
        }

        // Only after every fee-exempt address is final: the allow-list can never change again.
        if (vm.envOr("RENOUNCE_BEAD_OWNERSHIP", false)) d.bead.renounceOwnership();

        vm.stopBroadcast();

        console2.log("BeadToken          ", address(d.bead));
        console2.log("TreasuryForwarder  ", address(d.forwarder));
        console2.log("EkecheiriaPool     ", address(d.pool));
        console2.log("MatchRegistry      ", address(d.registry));
        console2.log("CosmicNecklace     ", address(d.necklace));
        console2.log("TierStaking        ", address(d.staking));
        console2.log("Resolver           ", d.resolver);
        console2.log("Consumer           ", d.consumer);
        console2.log("GaslessPaymaster   ", d.paymaster);
        console2.log("BeadToken owner (renounce after feeExempt list is final):", deployer);
    }
}
