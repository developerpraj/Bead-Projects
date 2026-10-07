# CRE workflow

`resolve-match/` is the Chainlink Runtime Environment workflow: an EVM log trigger on `MatchResultReceiver.MatchResolutionRequested`,
an API-Football read with DON consensus on the outcome code, and a signed report back to the receiver.

## Mocked locally (no CRE account, API key or faucet needed)

| Real dependency | Local stand-in |
|-----------------|----------------|
| API-Football | `resolve-match/mock/api-football-server.ts` (fixtures 1234 draw, 2001 home, 2002 away, 2003 postponed, 2004 not started, 2005 penalties; key `mock-api-football-key`) |
| CRE DON + KeystoneForwarder | `resolve-match/mock/don-relay.ts`, which runs the same steps as `main.ts` and delivers through an impersonated forwarder |
| Base Sepolia | `anvil --fork-url https://sepolia.base.org --chain-id 84532 --port 8546` (real UMA OOv3, EntryPoint and wallet factory) |

Run the full path (deploy to the fork, request, mock DON report, real UMA assertion, settlement, claims) with
`contracts/script/rehearse-fork-cre.ps1`; offline logic tests run with `npm test` in `resolve-match`.

## Placeholders to replace for the real network

| Where | Placeholder | Replace with |
|-------|-------------|--------------|
| `resolve-match/config.staging.json` | `receiverAddress` = zero address | deployed `MatchResultReceiver` address |
| `.env` | `API_FOOTBALL_KEY_ENV` empty | API-Football key |
| `.env` | `CRE_ETH_PRIVATE_KEY` | throwaway testnet key (already generated; fund it on Base Sepolia) |
| `../contracts/.env` | `CRE_FORWARDER` = zero address | mock forwarder (simulate) or forwarder (deployed), from `cre workflow supported-chains` |

Order: login, supported-chains, deploy contracts with the mock forwarder, `requestMatchResult`, fill `receiverAddress`,
`cre workflow simulate resolve-match --evm-tx-hash <tx> --broadcast --target staging-settings`, switch the receiver to the real
forwarder, `cre workflow hash`, `cre workflow deploy`, then `setExpectedWorkflowId` / `setExpectedAuthor` on the receiver.

## Production safety

The KeystoneForwarder is shared by every CRE workflow, so a receiver without identity checks would accept reports from anyone's workflow.
After `setExpectedWorkflowId` and `setExpectedAuthor`, call `requireWorkflowIdentity()` on the receiver (one-way: reports are then rejected
unless both are set). Set `CRE_KEEPER` to a hot key that may call `requestMatchResult`, and hand the receiver to the Council Safe
(`TRANSFER_RECEIVER_OWNERSHIP=true`). Never call `requireWorkflowIdentity` while the simulation forwarder is configured.
Run `scripts/verify-all.ps1` from the project root before shipping.
