# Necklace Chain ($BEAD) - V1 Architecture (Base, chain ID 8453)

Source of truth: the locked plan (Resolutions 1-17). This diagram covers the V1 "Guarded Mainnet Pilot".

## 1. System context

```mermaid
flowchart LR
    subgraph Client["Client (Sprint 3)"]
        TMA["Telegram Mini-App<br/>Next.js + wagmi/viem"]
        CSW["Coinbase Smart Wallet<br/>(ERC-4337, passkeys)"]
    end

    subgraph Gov["Governance (off-chain -> on-chain)"]
        SNAP["Snapshot space<br/>1 vote per Tier-3 wallet"]
        SAFE["Council Executor<br/>Gnosis Safe (3-of-5)"]
    end

    subgraph Base["Base L2 contracts"]
        BEAD["BeadToken<br/>ERC-20, 13.8B cap"]
        REG["MatchRegistry<br/>createMatch / renounceBootstrap"]
        FT["FactionToken (clone x2 per match)"]
        POOL["EkecheiriaPool<br/>vault + truce state machine"]
        NECK["CosmicNecklace<br/>ERC-721 (Rama Node)"]
        TIER["TierStaking<br/>18 / 33 / 99 BEAD"]
        FWD["TreasuryForwarder<br/>pass-through, no balance"]
        PAY["GaslessPaymaster (Sprint 2)"]
    end

    subgraph Oracle["Oracle pipeline"]
        API["Sports APIs"]
        CL["MatchResultReceiver<br/>Chainlink CRE (KeystoneForwarder)"]
        UMA["UMAOptimisticResolver<br/>OOv3, 30-min window"]
    end

    PG["Protocol Guild<br/>Base split 0xffaa...9A20"]

    TMA --> CSW --> POOL
    CSW --> NECK
    PAY -.sponsors UserOps.-> CSW
    SNAP -->|reads stake| TIER
    SNAP -->|passed vote| SAFE
    SAFE -->|createMatch, pause| REG
    REG -->|Clones.clone + initializeMatch| FT
    REG -->|initializeMatch + reward funding| POOL
    POOL -->|mint / burn| FT
    NECK -->|burn 54+54| FT
    POOL -->|1% Peace Tax| FWD
    UMA -->|slashed bonds| FWD
    FWD --> PG
    API --> CL --> UMA
    UMA -->|reportOutcome / settle| POOL
    TIER -->|Tier-2 bond check| UMA
    BEAD --- POOL
```

## 2. Match lifecycle (EkecheiriaPool state machine)

```mermaid
stateDiagram-v2
    [*] --> OPEN: initializeMatch (registry only)
    OPEN --> LOCKED: kickoff / lockMatch
    LOCKED --> PENDING_RESOLUTION: oracle reports provisional score
    PENDING_RESOLUTION --> DISPUTED: Tier-2 challenge (33 BEAD bond)
    DISPUTED --> SETTLED: UMA resolves (bond slashed to forwarder if frivolous)
    PENDING_RESOLUTION --> SETTLED: 30 min elapse, no dispute
    OPEN --> REFUNDED: cancelled / postponed
    LOCKED --> REFUNDED: cancelled / 48h oracle silence
    SETTLED --> [*]: claimSettlement (truce: principal + reward; else 1:1)
    REFUNDED --> [*]: claimRefund (1:1)
```

## 3. Deposit -> forge flow

```mermaid
sequenceDiagram
    actor Fan
    participant Pool as EkecheiriaPool
    participant Fwd as TreasuryForwarder
    participant FT as FactionToken
    participant Neck as CosmicNecklace

    Fan->>Pool: deposit(matchId, HOME|AWAY, amount)
    Note over Pool: lock affiliation (one side per wallet per match)
    Pool->>Fwd: 1% Peace Tax
    Pool->>FT: mint(net amount)
    Fan-->>Fan: trade rival tokens on DEX / P2P
    Fan->>Neck: forgeDiplomaticNecklace(matchId)
    Neck->>FT: burn(54 HOME) + burn(54 AWAY)
    Neck->>Pool: onForge(matchId, 54)
    Pool->>Pool: burn 108 BEAD principal permanently
    Neck-->>Fan: mint Rama Node NFT
    Note over Fan: forfeits that match's truce yield
```

## 3b. Claim flow and live-supply bonus

```mermaid
sequenceDiagram
    actor Holder
    participant Pool as EkecheiriaPool
    participant FT as FactionToken

    Holder->>Pool: claimSettlement(matchId, side)
    Note over Pool: requires SETTLED and 50 blocks since own deposit
    Pool->>FT: totalSupply() (live, after forge burns)
    Pool->>Pool: bonus = bonusRemaining[side] * balance / supply
    Pool->>FT: burn(holder, balance)
    Pool-->>Holder: principal + bonus (truce only)
```

## 3c. Gasless transaction flow (Sprint 2)

```mermaid
sequenceDiagram
    actor Fan
    participant TMA as Telegram Mini-App
    participant Bundler
    participant EP as EntryPoint v0.6
    participant PM as GaslessPaymaster
    participant Wallet as Coinbase Smart Wallet
    participant Pool as EkecheiriaPool

    Fan->>TMA: Stake 50 Beads
    TMA->>Bundler: UserOperation (paymasterAndData = PM)
    Bundler->>EP: handleOps
    EP->>PM: validatePaymasterUserOp
    Note over PM: checks factory, (target, selector) allowlist,<br/>per-op cap, sender and global daily budgets
    EP->>Wallet: execute / executeBatch (approve + deposit)
    Wallet->>Pool: deposit(matchId, side, amount)
    EP->>PM: postOp (refund unused budget)
    Note over PM,EP: Gas deposit (depositTo) pays for UserOps;<br/>separate locked stake (addStake) lets validation read PM storage
```

## 4. Staking tiers and governance scope

| Tier | Stake | Name | V1 role |
|------|-------|------|---------|
| 1 | 18 BEAD | The Chai | Basic participation / polls |
| 2 | 33 BEAD | The Chotki | Post dispute bond to challenge oracle result (slashed if frivolous) |
| 3 | 99 BEAD (99 seats) | The Master Council | Match whitelisting, dispute escalation, circuit breaker. No treasury control |

## 5. Deploy order (breaks the circular dependencies)

```mermaid
flowchart TD
    A[BeadToken] --> B[TreasuryForwarder]
    B --> C[BeadToken.setTreasuryForwarder]
    C --> D[EkecheiriaPool]
    D --> E[FactionToken implementation]
    E --> F[MatchRegistry]
    F --> G[CosmicNecklace]
    G --> H[TierStaking]
    H --> I[UMAOptimisticResolver + MatchResultReceiver]
    I --> J[Consumer set on resolver, resolver set on TierStaking]
    J --> K[EkecheiriaPool.wire - registry, necklace, resolver]
    K --> L[feeExempt: pool, staking, vesting wallets]
    L --> M[createMatch #1, then renounceBootstrap]
```

1. `BeadToken`, `TreasuryForwarder` (Protocol Guild Base split as constructor arg), then `setTreasuryForwarder` (once)
2. `EkecheiriaPool`, `FactionToken` implementation, `MatchRegistry`, `CosmicNecklace`, `TierStaking`
3. Oracle contracts (`UMAOptimisticResolver`, `MatchResultReceiver` with the CRE forwarder address), `setConsumer`, `TierStaking.setResolver`
4. `EkecheiriaPool.wire(registry, necklace, resolver)` (once)
5. Fee-exempt list, fund the resolver with bond currency, Paymaster gas float (Sprint 2)

## 5b. Oracle result codes and genesis vesting

Chainlink Functions was sunset, so results come from a Chainlink Runtime Environment (CRE) workflow in `cre/resolve-match`:

1. The receiver owner or the `requester` keeper calls `MatchResultReceiver.requestMatchResult(matchId, fixtureId)`, which emits `MatchResolutionRequested`.
2. The workflow's EVM log trigger fires (finalized confidence). Each node reads API-Football `/fixtures?id=`; the DON must agree on the outcome code.
3. The workflow signs a report `(uint64 chainSelector, uint256 requestId, uint256 matchId, uint8 outcome)` and the KeystoneForwarder calls `MatchResultReceiver.onReport`.
4. The receiver checks forwarder, chain selector, workflow id/author (once set) and the open request, then calls `UMAOptimisticResolver.proposeOutcome`.

The workflow (`cre/resolve-match/outcome.ts`) returns one `uint8`:

| Code | Meaning | API-Football statuses |
|------|---------|-----------------------|
| 1 | Home win | `FT`, `AET`, `PEN` with `teams.home.winner = true` |
| 2 | Away win | `FT`, `AET`, `PEN` with `teams.away.winner = true` |
| 3 | Draw | `FT` with no winner flag |
| 4 | Cancelled (refund) | `PST`, `CANC`, `ABD`, `AWD`, `WO` |
| error | Not final yet, nothing reported | `NS`, `1H`, `HT`, `2H`, `ET`, `BT`, `P`, `SUSP`, `INT`, `LIVE`, `TBD` |

Every result, including a cancellation, goes receiver -> resolver -> UMA assertion -> 30 minute window before the pool settles or refunds.

Receiver hardening: the KeystoneForwarder is shared by every CRE workflow, so after the real workflow is deployed the owner calls
`setExpectedWorkflowId`, `setExpectedAuthor` and then the one-way `requireWorkflowIdentity()`; from then on `onReport` reverts unless both are set
(`IdentityNotConfigured`). Never enable it while the simulation MockForwarder is configured (it supplies no workflow metadata).

Local verification without any CRE account: `cre/resolve-match/mock` (mock API-Football and a mock DON relay) plus `contracts/script/rehearse-fork-cre.ps1`
on an anvil fork of Base Sepolia, which runs request -> report -> real UMA OOv3 assertion -> settlement -> claims.

Team (cliff 1 year) and private-seed (cliff 6 months) allocations are minted straight into `BeadVestingWallet` contracts when `TEAM_BENEFICIARY` / `SEED_BENEFICIARY` are set at deploy time. Total vesting durations are configurable and still need confirming.

## 6. Locked V1 constraints

- Hard cap 13.8B BEAD; dust threshold 100 whole tokens; 1% Peace Tax; gamma >= 0.30 symmetry; 50-block deposit hold; 30-min challenge window; 48h oracle-silence refund.
- Pool TVL cap is a fixed BEAD amount set at match initialization.
- No monetary yield on the NFT; tenure gives voting weight (1x-6x), up to 30% fee rebate, cosmetic rank.
- Out of V1: PoST nodes, Space Engine, NFC hardware, ZK healthtech, LiquidityLocker (Phase 4).
