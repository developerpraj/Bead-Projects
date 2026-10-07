# Necklace Chain ($BEAD) - Plan, as locked and as built

This is the working plan carried through the build. The original planning log (17 numbered resolutions across six user documents)
was long and partly superseded; this file keeps every locked decision, marks what changed during the build, and links to the code.
For open work see [../HANDOFF.md](../HANDOFF.md); for diagrams see [ARCHITECTURE.md](ARCHITECTURE.md). The unabridged log is [PLAN_LOG.md](PLAN_LOG.md)
(historical; its top block lists what changed).

## 1. Product (V1 "Guarded Mainnet Pilot")

- Chain: Base (8453), rehearsed on Base Sepolia (84532). Not LitVM.
- One sport, one unbranded derby ("North Red" vs "North White"), one Truce Pool at a time, one Telegram Mini-App.
- Out of V1: PoST nodes, Space Engine, NFC hardware, ZK healthtech, multi-sport, LiquidityLocker (Phase 4).
- No professional audit for the pilot; instead a fixed per-pool TVL cap in BEAD set at match creation (`maxPoolCapBead`).
- No pre-sale language; initial distribution is liquidity seeding plus gameplay rewards.

## 2. Locked design decisions and where they live

| Decision | Final form | Code |
|----------|------------|------|
| Token | ERC-20, 13.8B hard cap, 1% Peace Tax on transfer, dust threshold 100 whole tokens, fee-exempt allow-list | `contracts/src/BeadToken.sol` |
| Treasury | Zero-discretion pass-through to Protocol Guild Base split `0xffaaCCFe120f3fC47f42102cF4F28e837cd49A20`; no balance kept | `TreasuryForwarder.sol` |
| Vault = pool | The Truce Pool is the vault: one-side affiliation lock per wallet per match, 1% tax, 1:1 faction-token receipts | `EkecheiriaPool.sol` |
| Match factory | `MatchRegistry.createMatch` clones two `FactionToken`s, funds the reward pool atomically; bootstrap period then `renounceBootstrap` hands authority to the Council Executor | `MatchRegistry.sol`, `FactionToken.sol` |
| Forge | Burn 54 Home + 54 Away faction tokens (privileged `burn`, no approve), then pool burns the matching 108 BEAD principal permanently; mint Rama Node NFT | `CosmicNecklace.sol`, `EkecheiriaPool.onForge` |
| NFT utility | No monetary yield. Tenure (108-day cycles): voting weight 1x-6x, fee rebate 0/15/30%, cosmetic rank. Transfer resets tenure | `CosmicNecklace.sol` |
| Staking tiers | Chai 18, Chotki 33 (dispute bond, slashed if frivolous), Master Council 99 (99 seats, governance only, no treasury control) | `TierStaking.sol` |
| Truce | gamma >= 0.30 minority floor, 50-block deposit hold, 48h oracle-silence fail-safe refund, bonus paid from `bonusRemaining` over live supply | `EkecheiriaPool.sol` |
| Governance | Snapshot signalling (one vote per Tier-3 wallet) executed by a Gnosis Safe as the Council Executor; no on-chain Governor | deploy config |
| Gasless UX | Coinbase Smart Wallet, ERC-4337 EntryPoint v0.6, `GaslessPaymaster` (allow-list of target+selector, per-op and daily caps, gas deposit plus locked stake) | `GaslessPaymaster.sol`, `webapp/app/api/paymaster` |
| Vesting | Team 4y total / 1y cliff, seed 2y total / 6mo cliff (user approved) via `BeadVestingWallet` | `BeadVestingWallet.sol`, deploy script |
| Circular deploys | One-time setters: `BeadToken.setTreasuryForwarder`, `EkecheiriaPool.wire(registry, necklace, resolver)`, `resolver.setConsumer`, `TierStaking.setResolver` | `script/DeployV1Base.s.sol` |

## 3. Oracle (changed during the build)

Original plan: Chainlink Functions (`SportsFunctionConsumer`) + UMA OOv3. Chainlink Functions was sunset, so the oracle is now:

`requestMatchResult` (owner or keeper) -> CRE workflow (EVM log trigger, API-Football, DON consensus) -> KeystoneForwarder ->
`MatchResultReceiver.onReport` -> `UMAOptimisticResolver.proposeOutcome` -> pool provisional result -> 30-minute UMA window ->
`finalizeSettlement`. Cancellation also goes through the window.

- Outcome codes are `PoolTypes.Outcome`: 1 home, 2 away, 3 draw, 4 cancelled. A proposed "1 = done / 2 = cancelled" scheme was rejected because
  code 2 would settle as an away win.
- A proposed direct `cancelMatch` was rejected because it would bypass the dispute window.
- The forwarder is shared by all CRE workflows, so the receiver has a one-way `requireWorkflowIdentity()` (needs expected workflow id and author)
  and a `requester` keeper role so the owner can be the Safe.
- Resolver wraps `POOL.resolveDispute` in try/catch so bonds always settle even if the Council already refunded the match.
- Off-chain code: `cre/resolve-match` (`main.ts`, `outcome.ts`, `abi.ts`); local stand-ins in `cre/resolve-match/mock`.

## 4. Other changes versus the original plan

- `MatchFactionVault`, `PeaceTreasury`, `PoSTNodeRegistry`, `CosmicMilestoneOracle`, `MultisigOracleRelay`, `EmissionMath` are not built (retired or cut).
- `forgeDiplomaticNecklace(matchId)` takes a match id, not two faction addresses; `burnFrom` was dropped for a privileged `burn`.
- The pool is fee-exempt; the paymaster has no on-chain BEAD skim (it is ETH-funded and must be staked at the EntryPoint).
- Deploy script supports a Foundry keystore (`--account X --sender ADDR`), optional vesting wallets, `RENOUNCE_BEAD_OWNERSHIP`, CRE receiver options
  (`CRE_KEEPER`, `TRANSFER_RECEIVER_OWNERSHIP`).
- Fee-rebate cap is 30% (a "50%" summary bullet in one source document was wrong).

## 5. Build status

| Area | Status |
|------|--------|
| Contracts | Done. 129 Foundry tests pass (unit, fuzz, invariants, edge cases, deploy script, CRE receiver) |
| CRE workflow | Written, type-checked against `@chainlink/cre-sdk` 1.23, 14 offline tests. Never run in the CRE runtime (needs `cre login`) |
| Webapp | Done. 5 pages (home, truce-pool, forge, staking, profile) plus paymaster route; builds; 0 npm vulnerabilities; security headers |
| Local rehearsal | Done on anvil, and on an anvil fork of Base Sepolia with real UMA OOv3, EntryPoint and wallet factory (`rehearse-fork-cre.ps1`) |
| Real Base Sepolia deploy | Not done: needs funded key, CRE account, API key (see HANDOFF) |
| Mainnet | Not started: needs real addresses, legal, liquidity plan, optional audit |

## 6. Verification

`./scripts/verify-all.ps1` from the project root runs forge, the CRE type-check and tests, the webapp build and both npm audits.
Fork rehearsal: see [../cre/README.md](../cre/README.md).
