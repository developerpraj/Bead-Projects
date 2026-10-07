"use client";

import { useAccount, useConnect, useDisconnect, useReadContract } from "wagmi";
import { stakingAbi, beadAbi } from "@/lib/abi";
import { BEAD, STAKING } from "@/lib/config";
import { openInExternalBrowser, useTelegramUser } from "@/lib/useTelegramUser";
import { formatEther } from "viem";

const TIERS = ["No tier", "Chai", "Chotki", "Master Council"];

export default function Home() {
  const tgName = useTelegramUser();
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  const { data: bead } = useReadContract({
    address: BEAD,
    abi: beadAbi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });
  const { data: tier } = useReadContract({
    address: STAKING,
    abi: stakingAbi,
    functionName: "tierOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  return (
    <section className="space-y-6">
      <header>
        <h1 className="text-2xl font-semibold text-amber-300">Necklace Chain</h1>
        <p className="text-white/60">{tgName ? `Welcome, ${tgName}.` : "Welcome, traveller."}</p>
      </header>

      {!isConnected ? (
        <div className="space-y-3 rounded-xl border border-white/10 p-4">
          <p className="text-sm text-white/70">
            Create or connect your Coinbase Smart Wallet. It signs with a passkey, so there is no seed phrase.
          </p>
          <button
            className="w-full rounded-lg bg-amber-400 py-3 font-medium text-black disabled:opacity-50"
            disabled={isPending || connectors.length === 0}
            onClick={() => connect({ connector: connectors[0] })}
          >
            {isPending ? "Connecting..." : "Connect wallet"}
          </button>
          {tgName && (
            <button className="w-full text-xs text-white/50 underline" onClick={() => openInExternalBrowser()}>
              Passkey prompt not working? Open in your browser
            </button>
          )}
        </div>
      ) : (
        <div className="space-y-3 rounded-xl border border-white/10 p-4 text-sm">
          <p className="break-all text-white/70">{address}</p>
          <p>BEAD balance: {bead !== undefined ? formatEther(bead) : "..."}</p>
          <p>Tier: {tier !== undefined ? TIERS[tier] : "..."}</p>
          <button className="text-white/50 underline" onClick={() => disconnect()}>
            Disconnect
          </button>
        </div>
      )}

      <p className="text-xs text-white/40">
        One derby, one Truce Pool. Pick a side, hold to the final whistle, and a balanced pool unlocks the truce bonus.
      </p>
    </section>
  );
}
