import { CHAIN_ID, PAYMASTER } from "@/lib/config";

// ERC-7677 endpoint for EntryPoint v0.6. The GaslessPaymaster needs no signature, so its
// address is the whole paymasterAndData; spending limits and the call allowlist live on-chain.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

type RpcBody = { id: number | string | null; method: string; params?: unknown[] };

const reply = (id: RpcBody["id"], payload: object) =>
  Response.json({ jsonrpc: "2.0", id, ...payload }, { headers: CORS });

export function OPTIONS() {
  return new Response(null, { status: 204, headers: CORS });
}

const ZERO = "0x0000000000000000000000000000000000000000";

export async function POST(req: Request) {
  let body: RpcBody;
  try {
    body = (await req.json()) as RpcBody;
  } catch {
    return reply(null, { error: { code: -32700, message: "Parse error" } });
  }
  if (!body || typeof body !== "object" || typeof body.method !== "string") {
    return reply(null, { error: { code: -32600, message: "Invalid request" } });
  }
  const { id, method, params } = body;

  if (method !== "pm_getPaymasterStubData" && method !== "pm_getPaymasterData") {
    return reply(id, { error: { code: -32601, message: "Method not found" } });
  }
  const chainId = Number(params?.[2]);
  if (chainId !== CHAIN_ID) {
    return reply(id, { error: { code: -32602, message: "Unsupported chain" } });
  }
  // Never hand out the zero address as paymasterAndData when the deployment is not configured.
  if (PAYMASTER === ZERO) {
    return reply(id, { error: { code: -32603, message: "Paymaster not configured" } });
  }
  return reply(id, { result: { paymasterAndData: PAYMASTER, isFinal: true } });
}
