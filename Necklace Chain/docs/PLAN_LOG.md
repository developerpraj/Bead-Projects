# >>> BUILD STATUS UPDATE (2026-10-07) - READ FIRST, KEEP THIS FILE FOREVER <<<
Everything below this block is the original planning log (historical). Where it conflicts with this block, THIS BLOCK WINS.
Repo copies: `Necklace Chain/docs/PLAN.md` (curated plan), `Necklace Chain/HANDOFF.md` (pending items), `docs/ARCHITECTURE.md`, `cre/README.md`.

Built and verified: all V1 contracts (129 Foundry tests), CRE workflow (type-check + 14 tests), Telegram webapp (builds, 0 vulns),
paymaster, deploy script, mocked fork rehearsal on a Base Sepolia fork with real UMA OOv3. Nothing deployed to a real network.

Changes vs the log below:
- Chainlink Functions was SUNSET -> oracle is Chainlink Runtime Environment (CRE): `MatchResultReceiver` (+ `oracles/cre/ReceiverTemplate`) replaces
  `SportsFunctionConsumer`; off-chain workflow in `cre/resolve-match`. Flow: requestMatchResult -> CRE workflow -> KeystoneForwarder -> onReport ->
  UMAOptimisticResolver -> 30-min window -> finalizeSettlement. Outcome codes stay PoolTypes.Outcome (1 home, 2 away, 3 draw, 4 cancelled).
- Receiver hardening: shared forwarder => one-way `requireWorkflowIdentity()` + `requester` keeper role; owner can be the Council Safe.
- Retired/cut: MatchFactionVault, PeaceTreasury, PoSTNodeRegistry, CosmicMilestoneOracle, MultisigOracleRelay, EmissionMath, SportsFunctionConsumer.
- `forgeDiplomaticNecklace(matchId)`; pool burns 108 BEAD principal via `onForge`; pool fee-exempt; bonus from `bonusRemaining` over live supply.
- Deploy via one-time setters (not mutable setMatchRegistry); keystore signing; vesting team 4y/1y cliff, seed 2y/6mo cliff (user approved).
- Paymaster: EntryPoint v0.6, Coinbase Smart Wallet factory, ETH-funded (deposit + stake), no on-chain BEAD skim.
- Pending (user-only): cre login + deploy access, faucet funding, API-Football key, forwarder addresses, real wallets/Safe, Protocol Guild contact,
  legal/audit/liquidity, bundler staking test, on-device test. See HANDOFF.md.
- Rules: NO git in this project; never leave deploy env vars in the persistent shell; run `scripts/verify-all.ps1` to verify.


# Plan: Necklace Chain ($BEAD) - Engineering PRD-aligned build

## Context / document history
User has supplied FIVE documents so far, each refining/overriding the last:
1. Whitepaper ("The Cosmic Protocol on LitVM") - base tokenomics.
2. Master Execution & Project Plan - 4-phase/12-month roadmap + pre-mainnet
   constraints checklist + advanced mechanisms (oracle/paymaster/MEV/legal).
3. Oracle Architecture & Data Ingestion Plan - Dual-Layer oracle
   (Chainlink Functions Layer 1 + UMA-style optimistic dispute Layer 2),
   5-state match lifecycle, Space Engine milestone oracle.
4. Engineering PRD & Security Threat Model - explicit Sprint 1/2/3 ordering,
   exact contract/function names, hardened threat-model fixes, 4 mandatory
   Foundry test names.
5. **"Necklace Chain ($BEAD): Master Protocol Specification, Whitepaper &
   Execution Architecture"** - single compiled document merging docs 1-4
   plus literal reference Solidity code for `CosmicNecklace.sol`.
6. **V1 De-Risking & MVP Scope Resolution (latest, supersedes prior scope -
   see "V1 MVP SCOPE LOCK" section below)** - resolves every open question
   from Further Considerations: the Forge-burn contradiction, governance
   naming drift, regulatory (Howey) exposure, LitVM/oracle infra risk,
   sports IP risk, and cuts scope down to a single shippable V1.

This plan now treats document 5's embedded Solidity as the canonical
reference implementation for `CosmicNecklace.sol`, corrected further by
document 6's wrapped-vault mechanic (see below). Document 6 OVERRIDES the
Sprint 1/2/3 full scope with a much smaller V1 MVP - treat everything below
"V1 MVP SCOPE LOCK" as the current target; everything else in this file is
historical/V2+ reference.

## V1 MVP SCOPE LOCK (document 6 - THIS IS THE CURRENT TARGET)
Document 6 resolved every open question and cut scope to a single
shippable V1. Everything in this section supersedes conflicting detail
elsewhere in this file (which is kept for historical traceability).

### Resolution 1: Forge-burn contradiction -> wrapped vault mechanic
`$BEAD` stays the ONE liquid currency. Home/Away "faction beads" are
**ephemeral wrapped ERC-20 tokens minted 1:1 by a `MatchFactionVault`**:
depositing 54 `$BEAD` into the vault mints 54 Home (or Away) wrapped tokens
and LOCKS the underlying `$BEAD` in the vault. Calling
`forgeDiplomaticNecklace()` burns 54 Home + 54 Away wrapped tokens, which
triggers the vault to PERMANENTLY BURN the 108 locked `$BEAD` (via
`BeadToken.burn`) and mints the `CosmicNecklace` NFT. This reconciles
"burn 108 liquid $BEAD" with "burn 54+54 faction tokens" - they're the same
event. New contract: `MatchFactionVault.sol` (replaces the earlier
`FactionToken.sol` free-standing per-team token idea - wrapped tokens are
vault-minted, not independently mintable). Vault also needs a redemption/
unwrap path (burn wrapped token -> reclaim locked $BEAD) for users who
deposit but never forge, so liquidity isn't stuck.

### Resolution 2: Governance taxonomy LOCKED (naming drift resolved)
- Tier 1 (18 $BEAD staked): **The Chai** - basic participation/polling.
- Tier 2 (33 $BEAD staked): **The Chotki** - service/telemetry routing nodes.
- Tier 3 (99 $BEAD staked, 99 seats): **The Master Council** - governance,
  votes on treasury grants.
- VIP NFT (108 $BEAD burned via the vault mechanic above): **The Rama Node**
  - the forged NFT conferring ecosystem status.
"Guru Node" is DEPRECATED - do not use. "Divine Attributes" was an earlier
name for Tier 3, also superseded by "The Master Council".

### Resolution 3: Regulatory (Howey) de-risking - MAJOR DESIGN CHANGE
- **Eliminate passive holding yield entirely.** The `M = 1 + k*floor(T_held
  /108)` monetary yield multiplier is REMOVED from `CosmicNecklace`. Replace
  with non-monetary "consumptive game utility": fee discounts on future
  forges, governance voting weight, and visual NFT trait evolution. The
  `_update`-triggered reset-on-transfer behavior stays (still resets
  whatever non-monetary trait/discount state exists on transfer) but it no
  longer feeds a yield/reward calculation.
- **Treasury model DECIDED: Hardcoded Routing (Zero Discretion), not the
  Foundation/whitelist-veto model.** Rationale: the Foundation model
  requires an actual legal entity to exist BEFORE any contract ships
  (jurisdiction choice, charter, registration) - that contradicts the V1
  ruthless-scope-cut philosophy. Hardcoded routing gives equal or stronger
  regulatory insulation (literally zero governance surface over treasury
  funds - nobody votes on where money goes, ever) without that
  prerequisite. V2+ upgrade path: migrate to a Cayman Foundation/Swiss
  Verein + whitelist-veto model once volume justifies the legal spend.
  **Contract implication**: `PeaceTreasury.sol` has NO `COUNCIL_ROLE`
  voting/withdrawal mechanic at all. It holds a hardcoded (deploy-time,
  immutable or near-immutable), small list of pre-vetted public-goods
  recipient addresses with fixed split percentages, and mechanically
  forwards the skimmed 1% to them (e.g. a permissionless `distribute()`
  call anyone can trigger, or auto-forward on receipt) - no admin
  discretion, no Tier-3 vote over allocation, ever.
- **Master Council (Tier 3) governance scope narrowed**: keeps its
  protocol-governance role (parameter votes, dispute oversight tied to
  Tier staking) but has ZERO vote over treasury fund allocation - that's
  now purely mechanical per the hardcoded routing decision above.
- **No pre-sale language.** Frame initial distribution as liquidity seeding
  + active gameplay rewards, not an investment opportunity (marketing/legal
  concern, not a contract mechanism, but affects any TGE-adjacent code).

### Resolution 4: LitVM/oracle infra realities -> V1 fallback architecture
Assuming Chainlink Functions/UMA exist on LitVM at launch is a single-point-
of-failure risk (new rollup, oracles rarely deploy day 1). **V1 drops
`ChainlinkMatchConsumer.sol` and `UmaDisputeEscalator.sol` entirely** in
favor of a simple **`MultisigOracleRelay.sol`**: N-of-M trusted signers post
the match outcome on-chain, still gated by the same 30-minute optimistic
dispute window (Tier-2 Chotki node holders can still challenge). Chainlink/
UMA integration becomes a V2+ upgrade path once LitVM's oracle ecosystem
matures (or once a decision is made to launch V1 on an established L2
instead - see Further Consideration below, STILL UNDECIDED).

### Resolution 10: Chain pragmatism - **CONFIRMED by user**
V1 deployment is LOCKED onto **Base** (chain ID 8453), not LitVM. Real
Chainlink Functions + UMA Optimistic Oracle V3 pipeline is CONFIRMED to
replace `MultisigOracleRelay.sol` entirely:
- Ingestion: Chainlink Functions DON queries sports APIs (Sportradar/Opta),
  aggregates, posts result on-chain.
- Dispute/settlement: UMA OOv3 posts the score as a bonded optimistic
  assertion with a 30-min challenge window; anyone can bond-challenge an
  anomalous/cancelled-match result; undisputed assertions auto-settle the
  Truce Pool + route the 1% fee; disputed ones escalate to UMA's DVM vote.
- Treasury: `TreasuryForwarder.sol`'s `_publicGoodsEoa` constructor param
  is CONFIRMED as Protocol Guild's verified Base split contract address:
  `0xffaaCCFe120f3fC47f42102cF4F28e837cd49A20` (see Resolution 9 - already
  independently verified via Protocol Guild's official docs).
- AA: **Coinbase Smart Wallet CONFIRMED** (passkey/FaceID/TouchID, native
  Base paymaster gas sponsorship) over ZeroDev/Biconomy/Alchemy.
- Oracle contract naming UPDATED (latest, more detailed naming):
  `oracles/SportsFunctionConsumer.sol` (Chainlink Functions client) +
  `oracles/UMAOptimisticResolver.sol` (OOv3 assertion/30-min challenge
  handler) - replaces the earlier `ChainlinkMatchConsumer.sol` +
  `UmaDisputeEscalator.sol` naming. `MultisigOracleRelay.sol` fully removed.

**All three gap-audit contradictions are NOW RESOLVED - see Resolutions
11-13 below.**

### Resolution 11: Self-forging loophole FIXED (Single-Faction Affiliation Lock)
`MatchFactionVault.sol` enforces an immutable per-match-per-wallet
affiliation lock:
```solidity
enum Faction { NONE, HOME, AWAY }
mapping(uint256 => mapping(address => Faction)) public userAffiliation;
error AffiliationAlreadyLocked(Faction chosenFaction);
error InvalidFactionSelection();

function depositAndMint(uint256 matchId, Faction faction, uint256 beadAmount)
    external nonReentrant {
    if (faction == Faction.NONE) revert InvalidFactionSelection();
    Faction current = userAffiliation[matchId][msg.sender];
    if (current == Faction.NONE) {
        userAffiliation[matchId][msg.sender] = faction;
    } else if (current != faction) {
        revert AffiliationAlreadyLocked(current);
    }
    _processDeposit(matchId, faction, beadAmount); // pulls BEAD, 1% tax, mints faction token 1:1
}
```
First deposit for a given `matchId` permanently locks that wallet to one
side; depositing for the other side reverts. Forces genuine P2P/DEX
trading to assemble the 54+54 needed to forge - restores the core
cross-fandom game mechanic. (Sybil via a second wallet still costs real
capital/slippage splitting across both vaults - acceptable residual risk,
not a loophole that defeats the mechanic for ordinary users.)

### Resolution 12: Non-monetary consumptive utility CONCRETELY DEFINED
Replaces the removed `CYCLE_BOOST_BPS`/monetary `yieldMultiplier` entirely
- `CosmicNecklace.sol` now exposes three purely non-monetary, read-only
functions, all driven by `T_held` (reset to 0 on any transfer, per the
existing `_update` override):
```solidity
function getTenureCycles(uint256 tokenId) public view returns (uint256) {
    uint256 heldTime = block.timestamp - lastTransferTimestamp[tokenId];
    return heldTime / 108 days;
}
function getVotingWeight(uint256 tokenId) external view returns (uint256) {
    uint256 cycles = getTenureCycles(tokenId);
    if (cycles > 5) cycles = 5;
    return 1 + cycles; // 1x to 6x, caps at 540 days (5 cycles)
}
function getFeeDiscountBps(uint256 tokenId) external view returns (uint256) {
    uint256 cycles = getTenureCycles(tokenId);
    if (cycles >= 3) return 3000; // 30% - AUTHORITATIVE cap (see note)
    if (cycles >= 1) return 1500; // 15%
    return 0;
}
```
1. **Governance weight scalar** - W = 1 + min(floor(T_held/108days), 5),
   caps at 6x influence on protocol-parameter votes (e.g. Tier-3 match
   whitelisting), resets to 1x on transfer.
2. **Protocol fee rebate tier** - 0% (<108d) / 15% (108-215d) / 30% (216d+,
   capped) discount on future match-entry fees. **NOTE: an earlier summary
   bullet in this same user message said "up to 50% discount" but the
   actual coded `getFeeDiscountBps` caps at 30% - treating 30% as
   authoritative since it's the concrete, coded version; flagged as a
   minor inconsistency to the user, not blocking.**
3. **Dynamic on-chain cosmetic rank** (metadata/SVG only, zero economic
   value) - Cycle 0 "Initiate" -> 1 "Ascendant" -> 2 "Solar" -> 3+ "Galactic".
No token payouts anywhere in this mechanic - Howey passive-yield risk from
Resolution 3 is now concretely closed, not just stated in principle.

### Resolution 13: Stale scope pruning CONFIRMED + operational parameters locked
- `PoSTNodeRegistry.sol` and `CosmicMilestoneOracle.sol` REMOVED from the
  repo/build entirely - confirmed cut, not just deferred.
- **Tier 2 (Chotki, 33 $BEAD) role REDEFINED for V1**: stays in
  `TierStaking.sol` as a plain stake threshold, sole purpose = posting an
  **Optimistic Dispute Bond** to challenge a Chainlink-reported score via
  UMA OOv3 within the 30-min window. If the dispute is upheld, bond
  returned + challenge reward; if the challenge is rejected (malicious/
  frivolous), the 33 $BEAD stake is SLASHED. (New mechanic: slashing on
  losing a dispute - ties into whichever contract resolves the UMA
  dispute outcome, likely `UMAOptimisticResolver.sol`.)
- **Master Council bootstrap problem SOLVED**: `MatchFactionVault.sol`
  (or a shared registry) has a `bootstrapPeriod` boolean; deployer is
  authorized to whitelist Match #1 directly while `bootstrapPeriod` is
  true; after Match #1 settles and the first Rama Nodes are forged,
  deployer calls `renounceBootstrap()`, permanently transferring match-
  whitelisting authority to the Master Council (Tier 3) from then on.
- **Dust threshold units CONFIRMED**: 100 WHOLE $BEAD tokens = `100 * 1e18`
  raw base units (not literal 100 wei) - matches the original assumption.
- **Genesis allocation wallets**: `script/DeployV1Base.s.sol` reads 5
  destination addresses from env vars - `ECOSYSTEM_ADDR`, `TREASURY_ADDR`,
  `TEAM_VESTING_ADDR`, `LIQUIDITY_ADDR`, `SEED_VESTING_ADDR` - with
  deterministic local Foundry test-account defaults for local runs. Real
  addresses supplied by the user at actual deploy time, never guessed.
- **V1 pilot derby CONFIRMED**: "North Red" vs "North White" (North London
  rivalry, non-infringing cultural naming per Resolution 5).
- **Final sign-off items reconfirmed**: `feeExempt` allow-list (vaults,
  staking, treasury forwarder, paymaster) confirmed as-is;
  `LiquidityLocker.sol` stays deferred to Phase 4.

### Updated Clean V1 Contract Manifest (per latest user message)
```
contracts/
  src/
    BeadToken.sol              - ERC-20 fixed supply (13.8B hard cap)
    MatchFactionVault.sol      - faction minting + single-side affiliation lock
    FactionToken.sol           - ephemeral wrapped ERC-20 (burnable by vault)
    CosmicNecklace.sol         - ERC-721; 54+54 burn; tenure/voting/fee-discount
    TierStaking.sol            - 18 Chai / 33 Chotki (dispute bond) / 99 Council
    TreasuryForwarder.sol      - router -> Protocol Guild Base split
    oracles/
      SportsFunctionConsumer.sol  - Chainlink Functions client
      UMAOptimisticResolver.sol   - OOv3 assertion + 30-min challenge + slashing
  test/
    BeadToken.t.sol, MatchFactionVault.t.sol, CosmicNecklace.t.sol,
    OracleSettlement.t.sol
  script/
    DeployV1Base.s.sol         - injects Protocol Guild address + env-var wallets
```
### Resolution 14: Second gap-audit pass FULLY RESOLVED (architecture consolidated)
- **Vault/Pool merger**: `MatchFactionVault.sol` is RETIRED - **"the Truce
  Pool is the Vault."** `EkecheiriaPool.sol` now does everything: single-
  faction-lock deposit, 1% tax auto-route to `TreasuryForwarder`, mints
  liquid ERC-20 `FactionToken` receipts 1:1. Holding to settlement = Truce
  yield path; trading+burning in `CosmicNecklace` = forge path (forgoing
  that match's yield for permanent Rama Node status - explicit
  opportunity-cost tradeoff, not a free lunch).
- **`MatchRegistry.sol`** (NEW contract, singleton hub): stores match
  state/schedule/oracle addresses + bootstrap/Council authorization.
  `createMatch(matchId, kickoffTime, "North Red", "North White")` deploys
  two lightweight `FactionToken` clones via OZ `Clones.clone()` (minimal
  proxy - avoids redeploying full bytecode per match) and initializes
  match state in `EkecheiriaPool`. Deployer holds `createMatch` during
  bootstrap; `renounceBootstrap()` hands it to Tier 3 permanently
  (concretizes Resolution 13's bootstrap mechanic onto a real contract
  instead of the vague "vault or a shared registry" hedge).
- **`forgeDiplomaticNecklace` signature UPDATED** (matches the matchId-
  based redesign, replacing the stale per-team-whitelist signature from
  the original doc-5 reference code):
  ```solidity
  function forgeDiplomaticNecklace(uint256 matchId) external nonReentrant
      returns (uint256) {
      (address homeToken, address awayToken) = matchRegistry.getMatchTokens(matchId);
      if (homeToken == address(0)) revert InvalidMatch();
      IFactionToken(homeToken).burnFrom(msg.sender, 54 * 1e18);
      IFactionToken(awayToken).burnFrom(msg.sender, 54 * 1e18);
      uint256 tokenId = _nextTokenId++;
      lastTransferTimestamp[tokenId] = block.timestamp;
      necklaceLineage[tokenId] = NecklaceLineage(matchId, block.timestamp); // simplified struct: matchId+forgedAt, not addresses
      _safeMint(msg.sender, tokenId);
      emit NecklaceForged(msg.sender, tokenId, matchId);
      return tokenId;
  }
  ```
- **Redemption/unwrap path FULLY SPECIFIED** (pull-based `claimSettlement
  (matchId)`, funds never expire):
  - `OPEN` (pre-kickoff): early withdrawal, 1:1 unwrap minus already-routed
    1% tax; affiliation lock stays bound (no flip-flopping).
  - `LOCKED`/`PENDING_RESOLUTION`: redemptions frozen.
  - `SETTLED` + truce met (gamma>=0.30): burn token -> principal + equal-
    share Truce reward payout.
  - `SETTLED` + truce failed: burn token -> exact 1:1 principal, no yield.
  - `REFUNDED` (cancelled/postponed): burn token -> exact 1:1 principal.
- **Tier-2 dispute-bond slashing destination CONFIRMED**: 100% of a
  slashed 33 $BEAD bond (frivolous/overruled dispute) routes to
  `TreasuryForwarder.sol` (i.e. ultimately Protocol Guild) - not burned,
  not paid to counter-disputers, to avoid both a burn-incentive-to-dispute
  loop and a griefing-bounty vector.
- **Paymaster cold-start SOLVED**: deployer seeds a **Genesis Gas Float of
  0.05 ETH on Base** (~$150-200) at launch, covers an estimated 20,000+
  sponsored txns at Base's sub-cent gas costs - the 0.1% volume skim takes
  over as a sustaining flywheel after that.
- **Base Sepolia rehearsal CONFIRMED as part of Sprint 1**: dry run using
  `MockChainlinkFunctions.sol` (simulated HTTP payload), a local mock
  dispute resolver (mimics UMA callback), and a mock testnet forwarder
  address (replacing the mainnet Protocol Guild split for test runs) -
  before real Base mainnet deployment.
- **Audit posture CONFIRMED**: V1 is explicitly a **"Guarded Mainnet
  Pilot"** - no $50k+ professional audit for a single-derby test; instead
  `EkecheiriaPool.sol` hardcodes a **Maximum Pool Cap** (e.g. $10,000
  total TVL across both factions) to bound worst-case exposure if an
  undiscovered exploit exists. **MINOR OPEN NIT**: the cap is described in
  USD, but there's no live BEAD/USD price oracle for a brand-new token -
  the actual enforced cap needs to be denominated in a fixed $BEAD token
  amount decided at deploy time (a USD-equivalent estimate at genesis
  price), not a literal on-chain USD check. Flagging for confirmation,
  not blocking.

### Updated contract manifest (supersedes the prior "Clean V1" list)
`MatchFactionVault.sol` REMOVED (merged into `EkecheiriaPool.sol`).
`MatchRegistry.sol` ADDED (singleton hub, `Clones.clone()` factory for
per-match `FactionToken` pairs, bootstrap/Council authorization). Final
V1 contract set: `BeadToken.sol`, `MatchRegistry.sol`, `FactionToken.sol`
(clone template), `EkecheiriaPool.sol` (vault+pool+state-machine, now the
central staking contract), `CosmicNecklace.sol` (matchId-based forge),
`TierStaking.sol`, `TreasuryForwarder.sol`, `oracles/
SportsFunctionConsumer.sol`, `oracles/UMAOptimisticResolver.sol`.

**SPEC STATUS: fully resolved through TWO complete gap-audit passes. Only
the USD-vs-BEAD TVL cap denomination nit remains open (non-blocking).**

### Resolution 15: Code-review findings on EkecheiriaPool.sol ALL FIXED
User posted the full `EkecheiriaPool.sol` draft; I reviewed it and found 4
functional gaps + 2 minor nits. All resolved:
1. `initializeMatch(matchId, homeToken, awayToken, kickoffTime,
   maxPoolCapBead, initialReward)` ADDED, gated by new `onlyRegistry`
   modifier (checks `msg.sender == address(MATCH_REGISTRY)`) - without
   this, `matches[matchId]` was never populated and `deposit()` always
   reverted.
2. `oracleResolver` now set via constructor param (`_oracleResolver`)
   instead of never being set - fixes `onlyOracle`-gated functions being
   permanently uncallable.
3. `rewardPool` funding source DECIDED: `MatchRegistry.createMatch()`
   transfers $BEAD from the Ecosystem Allocation (or deployer wallet for
   the pilot) into `EkecheiriaPool` and sets `m.rewardPool = initialReward`
   via `initializeMatch()`. **ONE REMAINING SUBTLETY (minor, flagged but
   not blocking)**: the shown `initializeMatch()` code only sets the
   accounting field `m.rewardPool`, it doesn't itself pull/transfer the
   matching $BEAD balance into the contract - need to confirm
   `MatchRegistry.createMatch()` actually performs
   `BEAD_TOKEN.safeTransferFrom(fundingSource, address(ekecheiriaPool),
   initialReward)` atomically alongside the `initializeMatch()` call, or
   claims could revert on insufficient contract balance later.
4. **Reward-share denominator bug FIXED** (the most important catch):
   `claimSettlement()` now uses `IFactionToken(tokenAddress).totalSupply()`
   (live, shrinks as Forge burns tokens) instead of the frozen
   `m.totalHomeStaked`/`totalAwayStaked` - this was the fix that prevents
   forged-away reward shares from being permanently stuck; now correctly
   redistributes to remaining holders exactly as originally intended.
5. Minor nits fixed: TVL cap check now uses `netBead` (not gross `amount`)
   for consistency with the accumulator; explicit `if (faction ==
   Faction.NONE) revert InvalidFaction();` guard added to both
   `claimSettlement()` and `claimRefund()` instead of relying on
   incidental zero-balance behavior.

**SPEC STATUS: fully resolved through TWO gap-audit passes + one full code
review of the central contract. User has explicitly ended the design/review
phase and is ready to switch to an edit-capable execution mode. Only the
rewardPool-funding-transfer subtlety above remains as a tiny loose end to
verify once real code gets written - everything else is locked.

### Resolution 16: Final round - FactionToken clone pattern + governance bridge
- **`FactionToken.sol` rewritten as `Initializable`/`ERC20Upgradeable`**
  (fixes the Clones.clone()-vs-constructor bug from the prior round):
  `_disableInitializers()` in constructor locks the implementation;
  `initialize(name, symbol, address _pool, address _necklace)` sets BOTH
  authorized addresses - `ekecheiriaPool` (mint + burn) and
  `cosmicNecklace` (burn only). No AccessControl import needed, just two
  immutable-after-init address fields + `Unauthorized()` checks.
- **Privileged `burn()` standardized across the protocol** - `burnFrom()`
  (allowance-based) is DROPPED entirely. `CosmicNecklace.
  forgeDiplomaticNecklace()` now calls `burn(msg.sender, 54e18)` directly
  on both faction tokens (as an authorized burner), eliminating the need
  for a separate `approve()` transaction - keeps Forge to one tap, matching
  the frictionless Telegram UX goal.
- **V1 governance execution model DECIDED**: no on-chain DAO Governor (too
  much attack surface for a Guarded Mainnet Pilot). Instead: Snapshot.org
  space reads `TierStaking.sol` on Base (one vote per active 99-$BEAD
  Tier-3 wallet) for off-chain signaling -> passed proposals executed
  on-chain by a core-team Gnosis Safe (e.g. 3-of-5 multisig), which
  `MatchRegistry.sol`/`EkecheiriaPool.sol` recognize as the "Council
  Executor" address. Separates social consensus from on-chain security.
- `initializeMatch()`'s atomic reward-transfer requirement (flagged in
  Resolution 15) is confirmed handled: `MatchRegistry.createMatch()` will
  perform the `$BEAD` transfer funding `m.rewardPool` in the same tx as
  the clone deployments.
- **Packaging note**: `FactionToken.sol` now needs
  `@openzeppelin/contracts-upgradeable` installed ALONGSIDE the regular
  `@openzeppelin/contracts` package used by `BeadToken`/`CosmicNecklace`/
  etc. - add to the `forge install` list in Sprint 1 step 1.

**SPEC STATUS: genuinely complete.** Three full gap-audit rounds plus a
full code review of EkecheiriaPool.sol and FactionToken.sol have been done.
Further review from this point forward has diminishing returns from static
reading alone - the next most valuable check is empirical: `forge build`
and `forge test` against the real files once scaffolding begins, which
will surface anything static review missed. Ready for execution mode.

### Resolution 17: Circular constructor dependency (EkecheiriaPool <-> MatchRegistry)
Final static-review catch: `EkecheiriaPool`'s constructor takes an
immutable `_matchRegistry` address (used by `onlyRegistry`), but
`MatchRegistry.createMatch()` needs `EkecheiriaPool`'s address to call
`initializeMatch(...)` on it - neither can be deployed first if both
require the other's address as an immutable constructor arg. **Fix**:
make `EkecheiriaPool.matchRegistry` a mutable, owner-settable field
instead of `immutable`; deploy order becomes: deploy `EkecheiriaPool`
(placeholder/owner-only unset registry) -> deploy `MatchRegistry` (now
knows `EkecheiriaPool`'s real address) -> call
`EkecheiriaPool.setMatchRegistry(address)` once to close the loop (then
optionally lock further changes). This is a deploy-script sequencing
note, not a design-intent change - flagged so `script/DeployV1Base.s.sol`
gets written with the right order from the start.

**NO FURTHER STATIC-REVIEW ROUNDS PLANNED** - additional "any more gaps"
passes without new information have diminishing value; remaining issues
(if any) are best caught empirically via `forge build`/`forge test` once
real files exist, not through more read-throughs of pasted code.

### Resolution 5: Sports IP -> clean derby factions for V1
No real club names/crests/trademarks in V1 (UEFA/Premier League
cease-and-desist risk). Use cultural derby framing instead, e.g.
"North London Red vs. West London Blue" rather than "Arsenal vs. Chelsea".
Affects `MatchFactionVault` naming/metadata and all webapp copy. Official
club branding only pursued later once volume justifies licensing deals.

### Resolution 6: Ruthless V1 scope cut (supersedes Sprint 1/2/3 breadth)
**Dropped from V1 entirely** (was previously "deferred" or even in-scope -
now explicitly cut, not just deferred): ZK healthtech/dental data layer,
physical NFC necklace hardware manufacturing, live deep-space telemetry
PoST routing (full node software), `CosmicMilestoneOracle` (Space Engine
entirely cut for V1), multi-sport/multi-derby support, Chainlink/UMA oracle
integration (see Resolution 4).

**The Shippable V1 Product** (this is now the entire near-term build target):
1. **Contracts**: `BeadToken.sol` ($BEAD ERC-20, capped, fee-on-transfer +
   dust-reject), `MatchFactionVault.sol` (wrapped 54/54 mint-lock-burn),
   `CosmicNecklace.sol` (NFT, 54/54 burn via vault, NO monetary yield -
   consumptive utility only), `TierStaking.sol` (Chai/Chotki/Master Council
   - protocol governance only, NOT treasury allocation),
   `PeaceTreasury.sol` (hardcoded zero-discretion routing to a small
   deploy-time list of pre-vetted public-goods addresses - no voting, no
   COUNCIL_ROLE withdrawal mechanic),
   `MultisigOracleRelay.sol` (replaces Chainlink/UMA for V1).
2. **Oracle**: simple transparent multisig relay for match outcomes + the
   30-minute optimistic dispute window (Tier-2 Chotki can challenge).
3. **Frontend**: ONE Telegram Mini-App, ONE sport, ONE (cultural, unbranded)
   derby, ONE active Truce Pool (`EkecheiriaPool.sol`, scoped simply - no
   multi-match infrastructure needed for V1). Still needs SOME gasless UX,
   so `GaslessPaymaster.sol` + one AA SDK stays in V1 scope, simplified to
   a single sponsored flow rather than elaborate multi-match session keys.

### Open question raised back to user (their own closing question)
They asked: lock down the updated smart contract code (wrapped 54/54 burn)
first, OR map out the simplified Telegram user flow for the single pilot
match first? NOT YET ANSWERED - need user's pick before proceeding, and
note that in Ask/Plan mode actual files still can't be created - code can
be drafted in chat as a reference but needs an edit-capable mode to land in
the workspace.

### Resolution 7: Treasury governance model DECIDED (hardcoded routing)
Recommended and adopted: Hardcoded Routing (Zero Discretion) for V1, NOT
the independent-Foundation/whitelist-veto model - see full rationale in
Resolution 3 above. V2+ upgrade path: migrate to a Cayman
Foundation/Swiss Verein holding the treasury with a whitelist-veto model
once protocol volume justifies the legal formation cost.

### Resolution 8: Treasury mechanics hardened (no accumulating balance)
Refines Resolution 7/3 further - even a hardcoded-recipient design is
weaker if funds sit as an internal contract balance (regulators can still
call that "management of a common fund"). Locked-in mechanics:
- **No pooled balance.** The 1% fee is never allowed to accumulate inside
  a Necklace Chain contract. Two acceptable patterns:
  (a) inline forwarding - at the exact moment a fee-generating action
  happens (mint, forge, transfer), compute the 1% and transfer it directly
  to the recipient in the SAME transaction; or
  (b) if gas batching is needed on LitVM, an immutable `Splitter.sol` that
  anyone can permissionlessly trigger via a public `distribute()` to push
  funds out to the fixed recipient(s) - no custody is retained voluntarily,
  it's just a pass-through with a public flush function.
- **`TreasuryForwarder.sol`** - new contract: an immutable, unupgradeable
  V1 interface whose only job is "push incoming funds to the hardcoded
  public-goods address." `BeadToken`/`MatchFactionVault`/`EkecheiriaPool`
  only ever reference this forwarder's address, never a specific charity
  address directly. V1->V2 migration path: deploy a NEW forwarder (or point
  future match vaults at a Foundation multisig) without ever touching/
  redeploying the core `$BEAD` token contract. This REPLACES the earlier
  simple "`PeaceTreasury.sol` holds a hardcoded list" design - now it's
  `TreasuryForwarder.sol` (pure pass-through, no balance) referenced by
  the fee-generating contracts.
  **Design refinement**: the recipient address is NOT a literal hardcoded
  string in the Solidity source - it's passed as a `constructor(address
  _beadToken, address _publicGoodsEoa)` parameter, set once at deploy time
  via `script/Deploy.s.sol`, then stored as `immutable`. Same end result
  (unchangeable after deployment) but the actual recipient value lives in
  deployment config, not compiled into the source text - cleaner to review/
  audit and easier to re-target before mainnet without touching the
  contract body.
- **Tier 3 (Master Council) scope LOCKED to non-financial actions only**
  (replaces "protocol-governance role (parameter votes, dispute oversight)"
  with this explicit, narrower list - nothing here touches revenue or
  capital allocation):
  1. **Match Whitelisting** - vote to approve new derby pairings / deploy
     a new `MatchFactionVault` for an upcoming match.
  2. **Dispute Escalation** - final appeal layer if a Tier-2 Chotki node
     flags an optimistic oracle score within the 30-min challenge window
     (sits above `MultisigOracleRelay`'s dispute path).
  3. **Emergency Circuit Breaker** - vote to pause staking on a specific
     match pool if the real-world fixture is cancelled/delayed.
- **OPEN QUESTION - needs the user's real-world input, not a default**:
  which specific public-goods recipient / registered non-profit to
  inject as the V1 `TreasuryForwarder` constructor parameter. This is a
  real legal/business decision (actual wallet address, actual verified
  entity) that must come from the user - not something to fabricate or
  guess. Candidates investigated so far (see below) - STILL NOT ANSWERED.

### Resolution 9: Treasury recipient candidates investigated (verified via fetch)
I independently fetched official sources rather than trust pasted claims:
- **Internet Archive / Tor Project addresses pasted into chat**: COULD NOT
  verify either from the official donation pages I fetched (content was
  rendered via a dynamic widget, no literal address text surfaced). Not
  rejected outright, but NOT confirmed either - do not use without the user
  independently re-confirming directly from the primary source.
- **Protocol Guild** (suggested as a "crypto-native, L2-aware" alternative):
  CONFIRMED REAL AND LEGITIMATE via protocolguild.org and their official
  docs (protocol-guild.readthedocs.io/en/latest/03-donate.html) - funds
  190 Ethereum core contributors, backed by major orgs (EigenLayer,
  Optimism, Arbitrum, Starknet, zkSync, etc.), uses documented immutable
  split-contract (0xSplits) architecture. Got real, verified addresses:
  - Mainnet: `0x4EA88fa76848a8BBAB72613d4171df1eBcf68399` (vesting) /
    `0xdddd576bAF106bAAe54bDE40BCac602bB4a7cf79` (multisig, for non-ETH/ERC20)
  - L2s with vesting contracts: Arbitrum, Base, Optimism only.
  - L2s with multisig-only receipt: Polygon, Scroll, Shape, zkSync, Zora.
  **CRITICAL FINDING: LitVM is NOT on Protocol Guild's supported-chain list
  at all.** Their own docs explicitly say to "reach out... before making a
  pledge donation, so that we can help coordinate a test transaction" -
  i.e. they want direct contact before anything is sent, especially on an
  unlisted chain. This means the original "L2 monitoring void" risk is
  NOT automatically solved by picking Protocol Guild - the user would need
  to actually contact Protocol Guild (pledge@protocolguild.org or their
  Calendly) to confirm LitVM support/get guidance BEFORE wiring their
  address into the `TreasuryForwarder` constructor param.
- **Bottom line**: no recipient is confirmed yet. Next concrete step is a
  real-world action (contact Protocol Guild, or independently re-verify
  Internet Archive/Tor Project's address from a primary source, or revisit
  whether V1 should deploy on a chain Protocol Guild actually supports -
  ties back to the still-undecided "Chain Pragmatism" item in Resolution 4).

### Still can't write files (Ask/Plan mode)
Workspace root: c:\Users\eu01242003\OneDrive - State of Minnesota - MN365\Desktop\proj
(currently empty). Docs still need saving to `Necklace Chain/docs/` once
an edit-capable mode is available - queued as the first scaffolding step.



## CosmicNecklace/FactionBead design CORRECTED (per literal reference code)
Document 5's section 8.2 provides actual `CosmicNecklace.sol` Solidity code,
which CORRECTS an earlier guess:
- Faction beads are **NOT** a single ERC-1155 contract with Home/Away token
  IDs (that was my earlier speculative design). Instead: each team/faction
  gets its OWN separate ERC-20-compatible token contract (an `IFactionBead`
  interface extending `IERC20` with `burnFrom`). `CosmicNecklace` keeps an
  `isApprovedFaction[address]` whitelist (admin-managed via
  `setFactionWhitelist`), and `forgeDiplomaticNecklace(address homeFaction,
  address awayFaction)` takes two WHITELISTED FACTION CONTRACT ADDRESSES,
  reverts if they're equal or unapproved, then burns `BEADS_PER_FACTION`
  (54 * 1e18) from the caller via `burnFrom` on EACH contract.
- **No separate 108-liquid-$BEAD burn inside Forge.** The reference code's
  Forge function only burns 54+54=108 units total ACROSS THE TWO FACTION
  TOKEN CONTRACTS - it does not also call `BeadToken.burnFrom`. This
  resolves (by replacing) my earlier two-part design (108 BEAD + 54/54
  faction beads as separate requirements) with a single unified mechanic.
  **FLAGGED AS A FURTHER CONSIDERATION**: confirm whether the whitepaper's
  "108 liquid $BEAD Crafting Burn" (2.1/2.3) is meant to be satisfied
  ENTIRELY by the 54+54 faction-token burn (as the reference code implies),
  or whether a THIRD burn of 108 generic $BEAD should still happen in
  addition. Defaulting to matching the literal reference code (no separate
  BEAD burn) unless told otherwise.
- New contract: `FactionToken.sol` - a reusable ERC-20 template (mint
  role-gated, `burnFrom` for the owning CosmicNecklace/holder) deployed
  ONCE PER TEAM/FACTION (e.g., "Arsenal Bead", "Chelsea Bead"), then
  whitelisted into `CosmicNecklace.isApprovedFaction`. Replaces the earlier
  planned single `FactionBead.sol` ERC-1155.
- `CosmicNecklace.sol` naming/constants now fixed to match reference code
  exactly: ERC721("Cosmic Necklace", "RAMA"); `BEADS_PER_FACTION = 54e18`;
  `CYCLE_DURATION = 108 days`; `CYCLE_BOOST_BPS = 500` (5%);
  `BASIS_POINTS = 10000`; `NecklaceLineage{homeFaction,awayFaction,forgedAt}`;
  events `NecklaceForged`, `HoldingReset`; custom errors `InvalidFaction`,
  `FactionsMustDiffer`, `FactionNotWhitelisted`; `_update` override resets
  `lastTransferTimestamp` exactly as previously planned (now confirmed
  twice over, independently, by two different user documents).

## Key decisions carried/updated by the PRD
- **Tooling**: Solidity ^0.8.20, Foundry (forge-std tests) - confirmed again.
- **Contract renamed**: `NecklaceNFT` -> `CosmicNecklace` (ERC-721), per PRD.
- **Forge function renamed & redesigned**: generic `Forge()` ->
  `forgeDiplomaticNecklace(uint256 homeBeadId, uint256 awayBeadId)`.
  RESOLVES the earlier open question about Home/Away faction beads
  (whitepaper 3.2): PRD's `test_ForgeRequiresOpposingFactions()` proves
  calling with two same-side IDs reverts, so faction beads ARE in Sprint 1
  scope now (previously deferred). Design: new `FactionBead.sol` (ERC-1155)
  where each tokenId has a registered `Side {Home, Away}`; forging requires
  burning 54 of a Home-side bead + 54 of an Away-side bead (54+54=108,
  matching the whitepaper's "108" bead motif) IN ADDITION to burning 108
  liquid $BEAD (whitepaper 2.1's original Crafting Burn still applies).
- **Fee model FLIPPED to fee-on-transfer**: PRD's `test_PeaceTaxRouting()`
  explicitly proves "exactly 1% of a 1,000 $BEAD *transaction* arrives at
  the... Treasury address" - a plain-transfer test, not a protocol-function
  test. This overrides the earlier "protocol-functions-only" decision.
  NEW design: `BeadToken.sol` overrides ERC-20 `_update` to skim 1% to
  `PeaceTreasury` on every transfer, enforcing the dust-reject
  (`V_tx >= 100` base units, else revert) in the same hook. To avoid
  breaking DEX/LP pools, vesting contracts, staking, and the treasury itself,
  maintain a `feeExempt[address]` allow-list (pool pairs, VestingWallet
  instances, TierStaking, PeaceTreasury, GaslessPaymaster vault) - standard
  practice for fee-on-transfer tokens. Flagged as a Further Consideration
  since this materially changes BEAD's DEX-listing behavior.
- **MEV protection hardened**: Block-Lock mechanism - staked tokens must sit
  in the Truce Pool for a minimum of 50 blocks before oracle resolution is
  accepted (replaces the earlier vaguer "3-block cooldown" idea).
  Symmetry constant gamma >= 0.30 unchanged.
- **Dispute function named**: `challengeOracleResult()` - callable only by
  addresses holding active Tier-2 Chotki Node status (33 $BEAD staked),
  only within the 30-minute Optimistic Challenge Window; escalates to the
  Layer-2 UMA-style dispute path from the Oracle Architecture doc.
- **State machine confirmed**: `OPEN -> LOCKED -> PENDING_RESOLUTION ->
  SETTLED | REFUNDED` (unchanged from Oracle Architecture doc).
- **`_update` override for T_held reset confirmed correct** (PRD section B
  independently specifies exactly the design already planned - no change).
- **Sprint 2 (Account Abstraction)**: Use a third-party AA SDK (ZeroDev,
  Biconomy, or Alchemy - PRD names all three, no single pick yet) for the
  ERC-4337 smart-account + session-key plugin, rather than writing a custom
  smart-account contract from scratch. Our own deliverable is
  `GaslessPaymaster.sol` (ERC-4337 `IPaymaster`) funded by a 0.1%-of-volume
  skim vault, sponsoring whitelisted Necklace Chain user operations, plus
  wiring to whichever AA SDK is chosen for "Matchday Session Keys" (time-
  bound, e.g. 4-hour scope). Which AA provider to use is a Further
  Consideration (non-blocking).
- **Sprint 3 (Telegram Mini-App) now concretely specified** (previously
  deferred as "different stack, later phase" - now has a real spec, tracked
  as Sprint 3 but still sequenced AFTER Sprints 1-2 per PRD's explicit
  "strict sequential order"):
  - Next.js (React) + Tailwind CSS, mobile-first
  - `@telegram-apps/sdk` for Telegram user/group context
  - `viem` + `wagmi` for contract interaction
  - AA infra provider (Biconomy / ZeroDev / Alchemy) for background Smart
    Account deployment tied to Telegram auth
  - UX flow: onboarding -> Matchday Session Key authorization (4h scope) ->
    Truce Pool tug-of-war UI -> gasless "Stake 50 Beads" via Paymaster

## Monorepo directory layout (updated)
Necklace Chain/
  docs/                            <- reference docs (save at Sprint 1 kickoff)
    MASTER_PROTOCOL_SPEC.md (doc 5, compiled spec - the canonical reference)
    whitepaper.md, execution-plan.md, oracle-architecture.md,
    engineering-prd.md (docs 1-4, for full traceability)
  contracts/                      <- Sprint 1 + Sprint 2 (Foundry project)
    foundry.toml, remappings.txt, .env.example, .gitignore
    src/
      BeadToken.sol                (fee-on-transfer + dust-reject + cap)
      FactionToken.sol             (reusable ERC-20 template, one deploy per
                                     team/faction, burnFrom for forging)
      CosmicNecklace.sol            (ERC-721 "Cosmic Necklace"/"RAMA"; matches
                                     doc 5 section 8.2 reference code exactly:
                                     T_held, yieldMultiplier,
                                     forgeDiplomaticNecklace burns 54+54 across
                                     two whitelisted FactionToken contracts)
      TierStaking.sol
      PeaceTreasury.sol
      EkecheiriaPool.sol            (5-state + DISPUTED substate, 50-block
                                     lock, gamma>=0.30, challengeOracleResult)
      PoSTNodeRegistry.sol
      GaslessPaymaster.sol          (Sprint 2)
      oracle/IMatchOracle.sol
      oracle/ChainlinkMatchConsumer.sol
      oracle/UmaDisputeEscalator.sol
      oracle/CosmicMilestoneOracle.sol
      libraries/EmissionMath.sol
    test/
      BeadToken.t.sol, FactionToken.t.sol, CosmicNecklace.t.sol,
      TierStaking.t.sol, PeaceTreasury.t.sol, EkecheiriaPool.t.sol,
      PoSTNodeRegistry.t.sol, GaslessPaymaster.t.sol,
      ChainlinkMatchConsumer.t.sol, UmaDisputeEscalator.t.sol,
      CosmicMilestoneOracle.t.sol
      mocks/MockFunctionsRouter.sol, mocks/MockOptimisticOracleV3.sol
    script/Deploy.s.sol
  webapp/                          <- Sprint 3 (Next.js Telegram Mini-App)
    package.json, next.config.js, tailwind.config.ts, tsconfig.json
    app/ (Next.js app router pages: onboarding, truce-pool, forge, profile)
    lib/ (viem/wagmi clients, @telegram-apps/sdk init, AA SDK wiring)

## Sprint 1 - Protocol Core (backend, do this first)
Group A - Core tokenomics:
1. Scaffold `Necklace Chain/contracts/` via `forge init`, foundry.toml
   (solc 0.8.20), `forge install` OpenZeppelin + Chainlink + UMA OOv3 iface.
2. `BeadToken.sol` - ERC20Capped(13.8B * 1e18); `_update` override applies
   1% fee-on-transfer to PeaceTreasury (skip if `feeExempt[from||to]`),
   reverts if `amount < 100 * 1e18`-scaled base units (dust); constructor
   mints Section 5.2 genesis split. *depends on 1*
3. `libraries/EmissionMath.sol` - pure halving E(t) and yield-multiplier M
   helpers. *depends on 1*
4. Vesting in `script/Deploy.s.sol` via OZ `VestingWallet` (Core Team 12-mo
   cliff linear; Private Seed 6-mo cliff); mark both fee-exempt. *depends on 2*
5. `FactionToken.sol` - reusable ERC-20 template (role-gated mint,
   `burnFrom`), one instance deployed per team/faction (e.g. "Arsenal Bead",
   "Chelsea Bead"); admin whitelists approved instances into
   `CosmicNecklace.isApprovedFaction`. *depends on 1*
6. `CosmicNecklace.sol` - matches doc 5 section 8.2 reference code: ERC721
   ("Cosmic Necklace","RAMA"); `lastTransferTimestamp[tokenId]` reset on
   transfer via `_update` override; `NecklaceLineage` struct; `yieldMultiplier`
   using `CYCLE_DURATION=108 days`/`CYCLE_BOOST_BPS=500`/`BASIS_POINTS=10000`;
   `forgeDiplomaticNecklace(address homeFaction, address awayFaction)` -
   reverts via `InvalidFaction`/`FactionsMustDiffer`/`FactionNotWhitelisted`
   custom errors, burns `BEADS_PER_FACTION` (54e18) from caller via
   `IFactionBead(faction).burnFrom` on EACH of the two whitelisted faction
   contracts, mints the NFT; reentrancy-guarded. *depends on 1, 3, 5*
7. `TierStaking.sol` - stake/unstake BEAD; Tier 1 (18) / Tier 2 (33) /
   Tier 3 (99, capped at 99 Master Council / Rama Node seats). Mark
   fee-exempt. *depends on 2*
8. `PeaceTreasury.sol` - receives the `_update`-skimmed 1% fee;
   `COUNCIL_ROLE` (active Tier-3 stakers) threshold withdrawal. Mark
   fee-exempt (receiving fees must not itself be taxed again). *depends on 7*

Group B - Truce Pool, oracle, PoST (still Sprint 1 - PRD calls it
"Ekecheiria Truce Pool logic" explicitly part of Sprint 1 backend core):
9. `oracle/IMatchOracle.sol` + `oracle/ChainlinkMatchConsumer.sol` - Layer 1
   Chainlink Functions DON consumer (`fulfillRequest` posts final score).
   *depends on 1*
10. `oracle/UmaDisputeEscalator.sol` - Layer 2; exposes the escalation path
    invoked by `EkecheiriaPool.challengeOracleResult()`. *depends on 7, 9*
11. `EkecheiriaPool.sol` - state machine `OPEN -> LOCKED -> PENDING_RESOLUTION
    -> SETTLED | REFUNDED`; `challengeOracleResult()` callable only by active
    Tier-2 Chotki Node holders within the 30-min window; **50-block
    minimum stake lock** before resolution accepted (MEV/flash-loan guard);
    gamma >= 0.30 minority-share floor; 48h total-oracle-silence Fail-Safe
    Refund; zero-fee REFUNDED payout path; 1% tax on SETTLED payouts (reuses
    BeadToken's transfer-tax path naturally since payouts are transfers).
    *depends on 2, 7, 8, 9, 10*
12. `oracle/CosmicMilestoneOracle.sol` - Space Engine Chainlink Functions
    consumer (NASA/CelesTrak/Space-Track); calls `pulseCosmicAttribute()` on
    `CosmicNecklace` for all active NFTs on verified milestone. *depends on 6, 9*
13. `PoSTNodeRegistry.sol` - Tier-2 Chotki node registration; `S_allocated`
    capped at `S_max`; `t_uptime` via heartbeat; `W_node = min(S_allocated,
    S_max) * t_uptime`; downtime resets multiplier. *depends on 7*

Group C - Sprint 1 verification:
14. Foundry tests - MUST include ALL named tests from BOTH the Engineering
    PRD (doc 4) and the Master Protocol Spec (doc 5), since neither doc said
    to replace the other's suite - treat as a merged superset:
    From doc 4:
    - `test_FailMintOverHardCap()` - minting token 13,800,000,001 reverts
    - `test_ForgeRequiresOpposingFactions()` - `forgeDiplomaticNecklace(homeA,
      homeA)` reverts
    - `test_PeaceTaxRouting()` - 1% of a 1,000 BEAD transfer arrives at the
      Treasury address exactly
    - `test_TrucePoolRefund()` - cancelled-match oracle report -> all staked
      BEAD withdrawable with zero fees
    From doc 5 (section 9, overlapping intent but distinct names/assertions):
    - `test_RevertMintExceedingCosmicCap()` - same hard-cap intent as
      `test_FailMintOverHardCap`, kept as a second explicit assertion
    - `test_SymmetryViolationRevertsTruce()` - gamma<0.30 fails the yield
      multiplier (whale-protection test, more explicit than earlier draft)
    - `test_TransferResetsHoldingMultiplier()` - moving a Rama Node resets
      the 108-day cycle boost to 1.0x
    - `test_DualFactionBurnAccuracy()` - forging burns exactly 54 tokens from
      BOTH whitelisted faction contracts and mints exactly one NFT
    - `test_OracleChallengeWindowHoldsFunds()` - payouts cannot execute until
      the 30-min challenge window fully elapses
    Plus previously-identified checklist/oracle tests: inflation-guard
    halving, storage-monopoly S_max cap, full 5-state(+DISPUTED) lifecycle,
    dispute escalation, 48h fail-safe refund, cosmic milestone pulse,
    50-block lock enforcement, fee-exemption allow-list correctness,
    vesting cliffs.
15. **Final Pre-Flight Deployment Checklist** (doc 5 section 10.2) - treat as
    a literal go/no-go gate before any testnet deployment, re-verified after
    all Sprint 1 tests pass:
    - [ ] ERC-20 total supply hard cap immutable at 13,800,000,000 $BEAD
    - [ ] 54 Home / 54 Away dual-burn enforced with active whitelisting
    - [ ] Ekecheiria Truce symmetry constant enforces gamma >= 0.30
    - [ ] ERC-4337 Paymaster gas sponsorship vault tested under simulated load
          (Sprint 2 item - gate applies before mainnet, not before Sprint 1)
    - [ ] 30-minute optimistic oracle challenge window functions on LitVM testnet
    - [ ] All transactions below 100 base units revert automatically
    - [ ] Initial DEX liquidity pools seeded with a 12-month lockup contract
          (see Further Considerations - new `LiquidityLocker.sol`, Phase 4 item)

## Sprint 2 - Account Abstraction (depends on Sprint 1 complete)
15. `GaslessPaymaster.sol` - ERC-4337 `IPaymaster`; gas vault funded by a
    0.1%-of-volume skim hook (separate from the 1% Peace Tax); sponsors only
    whitelisted Necklace Chain contract calls.
16. Pick + integrate one AA SDK (ZeroDev / Biconomy / Alchemy - see Further
    Considerations) for the Smart Account + session-key plugin; wire
    `GaslessPaymaster` as the sponsoring paymaster for that SDK's UserOps.
17. "Matchday Session Key" design: time-bound (4h) session key scoped to
    stake/predict calls only, via the chosen AA SDK's session-key module.

## Sprint 3 - Telegram Mini-App frontend (depends on Sprint 2 complete)
18. Scaffold `Necklace Chain/webapp/` - Next.js + Tailwind, `@telegram-apps/
    sdk`, `viem` + `wagmi`, chosen AA SDK's React hooks.
19. Onboarding flow: read Telegram ID -> auto-generate non-custodial Smart
    Account -> prompt Matchday Session Key authorization.
20. Truce Pool UI: live Home/Away tug-of-war bar backed by `EkecheiriaPool`
    on-chain state.
21. Gasless staking UI: "Stake 50 Beads" button routes through the AA
    SDK + `GaslessPaymaster`, zero gas to the user.

## Verification
- `forge build` / `forge test -vv` / `forge coverage` for `contracts/`
- Manual: `forge script script/Deploy.s.sol` on local anvil; run through
  forgeDiplomaticNecklace, an Ekecheiria pool cycle (incl. a disputed and a
  refunded match), and a plain BEAD transfer to confirm the 1% tax +
  dust-reject behave exactly per the PRD's 4 named tests
- Sprint 2/3 verification to be detailed once Sprint 1 is approved and
  underway (AA provider choice affects exact test/verification approach)

## Further Considerations - STATUS AFTER FULL RESOLUTION PASS
All ten numbered gaps from the gap-audit are now resolved (see Resolutions
10-13 above). Only ONE open item remains:
1. **EkecheiriaPool.sol omission** - flagged in Resolution 13's "Updated
   Clean V1 Contract Manifest" note. Needs explicit user confirmation
   that this was an oversight, not an intentional cut.
2. Minor inconsistency: fee-discount cap stated as "50%" in one summary
   bullet vs. "30%" in the actual coded `getFeeDiscountBps` - treating 30%
   as authoritative (it's the concrete/coded version) unless corrected.

Everything else previously listed here (BEAD-burn discrepancy, fee-exempt
list, FactionToken distribution, AA provider, Chainlink/UMA-on-LitVM,
LitVM RPC, LiquidityLocker, doc-naming drift) is now resolved - see
Resolutions 1-13 above for the final answers. Kept only as a historical
note that this file went through a full audit-and-close cycle.

## Status
SPEC FULLY LOCKED - zero open design questions. All gaps resolved across
13 resolutions. `EkecheiriaPool.sol` confirmed back in Sprint 1 scope,
fee-discount cap confirmed at 30%. User gave explicit go-ahead to begin
execution (`forge init`, scaffold repo, write `BeadToken.sol`/
`MatchFactionVault.sol`/`TreasuryForwarder.sol`) - BUT this entire
conversation has been in Ask mode (read-only, no file/terminal writes
permitted). Flagged clearly to user that execution cannot start until they
switch to an edit-capable mode (e.g. Agent mode) in their tool. Nothing in
the workspace has been created yet - `Necklace Chain/` directory still
does not exist on disk.
