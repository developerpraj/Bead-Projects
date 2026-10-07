"use client";

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { encodeFunctionData, formatEther } from "viem";
import { factionTokenAbi, necklaceAbi, poolAbi } from "@/lib/abi";
import { MATCH_ID, NECKLACE, POOL } from "@/lib/config";
import { useSponsoredCalls } from "@/lib/useSponsoredCalls";

const NEEDED = 54n * 10n ** 18n;

export default function Forge() {
  const { address, isConnected } = useAccount();
  const { send, isPending, error, isSuccess } = useSponsoredCalls();

  const { data: match } = useReadContract({
    address: POOL,
    abi: poolAbi,
    functionName: "getMatch",
    args: [MATCH_ID],
  });

  const { data: balances } = useReadContracts({
    contracts: match && address
      ? [
          { address: match.homeToken, abi: factionTokenAbi, functionName: "balanceOf", args: [address] },
          { address: match.awayToken, abi: factionTokenAbi, functionName: "balanceOf", args: [address] },
        ]
      : [],
    query: { enabled: !!match && !!address, refetchInterval: 5000 },
  });

  const home = (balances?.[0]?.result as bigint | undefined) ?? 0n;
  const away = (balances?.[1]?.result as bigint | undefined) ?? 0n;
  const ready = home >= NEEDED && away >= NEEDED;

  return (
    <section className="space-y-6">
      <header>
        <h1 className="text-xl font-semibold text-amber-300">Forge a Rama Node</h1>
        <p className="text-sm text-white/60">
          Burn 54 North Red and 54 North White tokens to forge a Cosmic Necklace. The 108 BEAD behind them is burned
          for good, and you give up that match&apos;s truce bonus.
        </p>
      </header>

      {!isConnected ? (
        <p className="text-sm text-white/60">Connect your wallet on the Home tab first.</p>
      ) : (
        <div className="space-y-3 rounded-xl border border-white/10 p-4 text-sm">
          <p>North Red: {formatEther(home)} / 54</p>
          <p>North White: {formatEther(away)} / 54</p>
          {!ready && (
            <p className="text-xs text-white/50">
              One wallet can only stake one side, so you need to acquire the rival tokens from another holder.
            </p>
          )}
          <button
            disabled={!ready || isPending}
            onClick={() =>
              send([
                {
                  to: NECKLACE,
                  data: encodeFunctionData({ abi: necklaceAbi, functionName: "forgeDiplomaticNecklace", args: [MATCH_ID] }),
                },
              ])
            }
            className="w-full rounded-lg bg-amber-400 py-3 font-medium text-black disabled:opacity-40"
          >
            {isPending ? "Confirm in wallet..." : "Forge necklace"}
          </button>
          {isSuccess && <p className="text-xs text-emerald-400">Forge submitted. Check your profile shortly.</p>}
          {error && <p className="text-xs text-red-400">{error.message}</p>}
        </div>
      )}
    </section>
  );
}
