"use client";

import { useSendCalls } from "wagmi";
import type { Call } from "viem";
import { PAYMASTER_URL } from "./config";

/** Sends a batch as one user operation; sponsored when a paymaster URL is configured. */
export function useSponsoredCalls() {
  const { sendCalls, ...rest } = useSendCalls();
  const send = (calls: Call[]) =>
    sendCalls({
      calls,
      capabilities: PAYMASTER_URL ? { paymasterService: { url: PAYMASTER_URL } } : undefined,
    });
  return { send, ...rest };
}
