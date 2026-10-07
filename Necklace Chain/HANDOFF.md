# Handoff - Necklace Chain ($BEAD)

Last updated: 2026-10-07. Read this first, then [docs/index.html](docs/index.html) (open in a browser: one-page guide for the public, the team and engineers, including the whitepaper), [docs/PLAN.md](docs/PLAN.md) (decisions and what changed; the full original planning log with a status block
on top is [docs/PLAN_LOG.md](docs/PLAN_LOG.md)), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
(diagrams, deploy order, oracle flow) and [cre/README.md](cre/README.md) (CRE workflow, mocks, placeholders).

## State in one paragraph

All V1 code is written and verified offline: contracts (129 Foundry tests, incl. 4 scenario simulations), CRE workflow (type-checked, 14 offline tests), Telegram Mini-App webapp
(builds, 0 vulnerabilities). A mocked end-to-end rehearsal passes on an anvil fork of Base Sepolia using the real UMA OOv3, EntryPoint v0.6 and Coinbase
wallet factory. Nothing has been deployed to a real network, and the CRE workflow has never run in the real CRE runtime.

## Run the checks

```powershell
./scripts/verify-all.ps1          # forge + CRE type-check/tests + webapp build + npm audits
./contracts/script/rehearse-fork-cre.ps1 ...   # fork rehearsal, parameters in the script header (needs anvil fork on :8546)
```

Tool locations (Windows, add to PATH per terminal): Foundry `%USERPROFILE%\.foundry\bin`, Node `%USERPROFILE%\.node`, CRE CLI `%USERPROFILE%\.cre\bin`.
npm needs `$env:NODE_OPTIONS="--use-system-ca"` (corporate TLS proxy; never disable strict-ssl).

## Pending - needs the owner (cannot be done by an agent)

1. `cre login` (browser + 2FA) and `cre account access` (deploy access approval).
2. Fund the throwaway Base Sepolia key (address in `cre/.env`, `0xF79ee340A9b8B49284C46Eeb8eAAd5542b52126A`) from a faucet. Delete or rotate it afterwards:
   the file sits in a OneDrive-synced folder.
3. Register an API-Football key and set `API_FOOTBALL_KEY_ENV` in `cre/.env`.
4. Run `cre workflow supported-chains`; note the Base Sepolia forwarder and mock forwarder addresses.
5. Then run the real sequence (order matters, see cre/README.md): deploy contracts with the MOCK forwarder -> `requestMatchResult` -> put the receiver
   address in `cre/resolve-match/config.staging.json` -> `cre workflow simulate resolve-match --evm-tx-hash <tx> --broadcast --target staging-settings` ->
   `setForwarderAddress(real forwarder)` -> `cre workflow hash` -> `cre workflow deploy` -> `setExpectedWorkflowId` + `setExpectedAuthor` ->
   `requireWorkflowIdentity()` (one-way; never while the mock forwarder is set).
6. Real-network checks that need hardware or third parties: paymaster staking against a real bundler, Telegram Mini-App and Coinbase Smart Wallet on a phone.

## Pending - decisions and real-world inputs for mainnet

- Real genesis wallets (`ECOSYSTEM_ADDR`, `TREASURY_ADDR`, `LIQUIDITY_ADDR`, vesting beneficiaries) and the Council Executor Gnosis Safe. The deploy script
  defaults are local test accounts: never deploy mainnet with them.
- Contact Protocol Guild before sending anything (their docs ask for a test transaction first).
- Base mainnet values to verify from primary sources before use: UMA OOv3 address, bond currency and `BOND_AMOUNT`, CRE chain name and selector,
  KeystoneForwarder address, Coinbase Smart Wallet factory.
- Pool TVL cap (`maxPoolCapBead`) is a fixed BEAD amount chosen at match creation; no USD oracle exists.
- Legal review, optional external audit, liquidity plan and `LiquidityLocker` (Phase 4, not built).
- Decide whether to move the API-Football key to Confidential HTTP (currently a normal secret, visible to node operators; accepted for the pilot).

## Known gaps and risks

- Strategic risks (demand, cold start, no team revenue, legal, costs) and mitigations are written up in the "Honest assessment" section of
  [docs/index.html](docs/index.html). It is internal: remove that section before sharing the page publicly.
- Simulation findings (real contracts, `contracts/test/ScenarioSimulations.t.sol`, case studies in docs/index.html): the bonus is an all-or-nothing cliff at a
  30% minority share, and a wallet can pad the weak side just past 30% to unlock it (profitable whenever the minority-side bonus rate is above about 1%).
  Payouts as designed otherwise. Open design decisions: smooth the cliff, per-wallet caps with verification, sponsor-funded bonus, reward sizing, and
  whether counsel sees the bonus as yield.
- Conclusion and recommendations (sections "Findings", "Alternatives", "Recommendations" in docs/index.html): the real gap is an outside payer, not code. Suggested
  path: finish the testnet run, run a no-money fan pilot with agreed stop numbers, secure a sponsor, fix the incentive design, then a capped pilot. Keep the engine,
  reposition to a sponsor-funded campaign (no token) with the open-source toolkit as a hedge.
- Future sectors (section "Future sectors" in docs/index.html, researched 2026-10-07 with sources): best real-world fits are parametric community cover through an existing
  provider, charity matching, a sports-for-peace non-profit campaign, and the open-source toolkit. No partner has been contacted; avoid outcome-betting designs.
- The CRE YAML files (`cre/project.yaml`, `secrets.yaml`, `resolve-match/workflow.yaml`) were written from the docs and not yet accepted by the CLI;
  `workflow.yaml` may need a `deployment-registry` entry.
- `receiverAddress` in `config.staging.json` and `CRE_FORWARDER` in `contracts/.env.example` are zero-address placeholders on purpose (the receiver
  constructor rejects a zero forwarder).
- The workflow ID depends on `config.staging.json`, so the receiver must exist before the workflow is hashed and deployed; identity enforcement therefore
  happens after deployment (the deploy script logs a warning until then).
- SDK mock-runtime tests need Bun, which is not installed; the workflow handler is only covered by the mock relay and, later, `cre workflow simulate`.
- Webapp environment: all `NEXT_PUBLIC_*` addresses default to the zero address until set (see `webapp/.env.example`).
- Branch coverage is about 68% (pool about 90%).

## Rules and gotchas for the next agent

- The user asked for NO git in this project. Do not run `git init`; libraries were installed with `forge install --no-git`.
- Never leave deploy environment variables set in a persistent shell: `GENESIS_GAS_FLOAT`, `UMA_OOV3`, `CRE_*` etc. change the deploy-script test
  (`verify-all.ps1` clears them first).
- Foundry: `vm.prank` and `vm.expectRevert` apply to the NEXT call (cache getters first); keep `vm.setEnv` scenarios in ONE test (process-global).
- Do not type private keys from memory; rehearsals use unlocked or impersonated anvil accounts.
- Write long command output to a file and read the file; very large terminal output overflows context.
- The persistent planning log lives in the Copilot memory file `/memories/session/plan.md` (keep it); `docs/PLAN.md` is the curated copy in the repo.
