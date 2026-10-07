import {
  EVMClient,
  HTTPClient,
  Runner,
  TxStatus,
  bytesToHex,
  consensusIdenticalAggregation,
  getNetwork,
  handler,
  hexToBase64,
  type EVMLog,
  type NodeRuntime,
  type Runtime,
} from "@chainlink/cre-sdk";
import { EVM_PB } from "@chainlink/cre-sdk/pb";
import { decodeEventLog, encodeAbiParameters, parseAbiParameters } from "viem";
import { REPORT_PARAMETERS, requestedEventAbi, requestedEventTopic } from "./abi";
import { assertFixtureId, outcomeFromApiFootball } from "./outcome";

type Config = {
  /** CRE chain name, e.g. ethereum-testnet-sepolia-base-1 */
  chainSelectorName: string;
  /** MatchResultReceiver address */
  receiverAddress: string;
  /** https://v3.football.api-sports.io (override to point at a mock while testing) */
  apiBaseUrl: string;
  gasLimit: string;
};

const API_KEY_SECRET_ID = "API_FOOTBALL_KEY";

// Runs on every node; consensus requires all of them to agree on the outcome code.
const fetchOutcome = (nodeRuntime: NodeRuntime<Config>, fixtureId: string, apiKey: string): number => {
  const resp = new HTTPClient()
    .sendRequest(nodeRuntime, {
      url: `${nodeRuntime.config.apiBaseUrl}/fixtures?id=${fixtureId}`,
      method: "GET" as const,
      multiHeaders: { "x-apisports-key": { values: [apiKey] } },
    })
    .result();

  if (resp.statusCode !== 200) throw new Error(`API-Football returned status ${resp.statusCode}`);
  return outcomeFromApiFootball(JSON.parse(new TextDecoder().decode(resp.body)), fixtureId);
};

const onRequested = (runtime: Runtime<Config>, log: EVMLog): string => {
  const decoded = decodeEventLog({
    abi: requestedEventAbi,
    data: bytesToHex(log.data),
    topics: log.topics.map((t) => bytesToHex(t)) as [`0x${string}`, ...`0x${string}`[]],
  });
  const { matchId, requestId, fixtureId } = decoded.args;
  runtime.log(`Resolution requested: match ${matchId}, request ${requestId}, fixture ${fixtureId}`);

  const network = getNetwork({ chainFamily: "evm", chainSelectorName: runtime.config.chainSelectorName });
  if (!network) throw new Error(`Unknown chain: ${runtime.config.chainSelectorName}`);

  const apiKey = runtime.getSecret({ id: API_KEY_SECRET_ID }).result().value;
  const outcome = runtime
    .runInNodeMode(fetchOutcome, consensusIdenticalAggregation<number>())(assertFixtureId(fixtureId), apiKey)
    .result();
  runtime.log(`Fixture ${fixtureId} resolved with outcome code ${outcome}`);

  // The chain selector in the payload lets the receiver reject a report replayed on another chain.
  const payload = encodeAbiParameters(parseAbiParameters(REPORT_PARAMETERS), [
    network.chainSelector.selector,
    requestId,
    matchId,
    outcome,
  ]);
  const report = runtime
    .report({ encodedPayload: hexToBase64(payload), encoderName: "evm", signingAlgo: "ecdsa", hashingAlgo: "keccak256" })
    .result();

  const write = new EVMClient(network.chainSelector.selector)
    .writeReport(runtime, {
      receiver: runtime.config.receiverAddress,
      report,
      gasConfig: { gasLimit: runtime.config.gasLimit },
    })
    .result();

  const txHash = bytesToHex(write.txHash || new Uint8Array(32));
  runtime.log(`Report written: txHash=${txHash} txStatus=${write.txStatus} receiverStatus=${write.receiverContractExecutionStatus}`);

  // Both can fail independently: the transaction, and the receiver's onReport (for example a match that is not locked yet).
  if (write.txStatus !== TxStatus.SUCCESS) throw new Error(`Transaction failed: ${write.errorMessage}`);
  if (write.receiverContractExecutionStatus === EVM_PB.ReceiverContractExecutionStatus.REVERTED) {
    throw new Error("Receiver onReport reverted; the request stays open and can be redelivered");
  }
  return `match ${matchId} reported as ${outcome}`;
};

const initWorkflow = (config: Config) => {
  const network = getNetwork({ chainFamily: "evm", chainSelectorName: config.chainSelectorName });
  if (!network) throw new Error(`Unknown chain: ${config.chainSelectorName}`);

  return [
    handler(
      new EVMClient(network.chainSelector.selector).logTrigger({
        addresses: [hexToBase64(config.receiverAddress)],
        topics: [{ values: [hexToBase64(requestedEventTopic)] }],
        confidence: "CONFIDENCE_LEVEL_FINALIZED",
      }),
      onRequested,
    ),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
