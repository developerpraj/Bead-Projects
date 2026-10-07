// Stand-in for the CRE DON: same steps as main.ts (read the event, fetch the fixture, map the outcome, encode the report),
// delivered through an impersonated forwarder on a local anvil. Use `cre workflow simulate` for the real thing.
import { createPublicClient, createWalletClient, decodeEventLog, encodeAbiParameters, http, parseAbi, parseAbiParameters } from "viem";
import { REPORT_PARAMETERS, requestedEventAbi, requestedEventTopic } from "../abi.ts";
import { assertFixtureId, outcomeFromApiFootball } from "../outcome.ts";

type Hex = `0x${string}`;

export type RelayOptions = {
  rpcUrl: string;
  /** Hash of the requestMatchResult transaction, like `cre workflow simulate --evm-tx-hash`. */
  requestTx: Hex;
  receiver: Hex;
  /** Address the receiver trusts; must be impersonated on the target anvil. */
  forwarder: Hex;
  apiBaseUrl: string;
  apiKey: string;
  chainSelector: bigint;
};

const onReportAbi = parseAbi(["function onReport(bytes metadata, bytes report)"]);

export async function relayOnce(o: RelayOptions): Promise<{ outcome: number; deliveryTx: Hex }> {
  const publicClient = createPublicClient({ transport: http(o.rpcUrl) });
  const walletClient = createWalletClient({ transport: http(o.rpcUrl) });

  const receipt = await publicClient.getTransactionReceipt({ hash: o.requestTx });
  const log = receipt.logs.find(
    (l) => l.address.toLowerCase() === o.receiver.toLowerCase() && l.topics[0] === requestedEventTopic,
  );
  if (!log) throw new Error("No MatchResolutionRequested log from the receiver in that transaction");

  const { matchId, requestId, fixtureId } = decodeEventLog({
    abi: requestedEventAbi,
    data: log.data,
    topics: log.topics as [Hex, ...Hex[]],
  }).args;

  const res = await fetch(`${o.apiBaseUrl}/fixtures?id=${assertFixtureId(fixtureId)}`, {
    headers: { "x-apisports-key": o.apiKey },
  });
  if (res.status !== 200) throw new Error(`API-Football returned status ${res.status}`);
  const outcome = outcomeFromApiFootball(await res.json(), fixtureId);

  const report = encodeAbiParameters(parseAbiParameters(REPORT_PARAMETERS), [o.chainSelector, requestId, matchId, outcome]);
  const deliveryTx = await walletClient.writeContract({
    account: o.forwarder,
    chain: null,
    address: o.receiver,
    abi: onReportAbi,
    functionName: "onReport",
    args: ["0x", report],
  });
  const done = await publicClient.waitForTransactionReceipt({ hash: deliveryTx });
  if (done.status !== "success") throw new Error("Receiver onReport reverted");
  return { outcome, deliveryTx };
}

if (import.meta.main) {
  const args = new Map<string, string>();
  for (let i = 2; i < process.argv.length; i += 2) args.set(process.argv[i].replace(/^--/, ""), process.argv[i + 1]);
  const need = (k: string) => {
    const v = args.get(k);
    if (!v) throw new Error(`missing --${k}`);
    return v;
  };

  const { outcome, deliveryTx } = await relayOnce({
    rpcUrl: need("rpc"),
    requestTx: need("tx") as Hex,
    receiver: need("receiver") as Hex,
    forwarder: need("forwarder") as Hex,
    apiBaseUrl: need("api"),
    apiKey: need("key"),
    chainSelector: BigInt(need("chain-selector")),
  });
  console.log(`Reported outcome ${outcome} in ${deliveryTx}`);
}
