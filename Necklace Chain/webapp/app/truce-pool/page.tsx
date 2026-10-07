"use client";

import { useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { encodeFunctionData, formatEther, parseEther } from "viem";
import { beadAbi, factionTokenAbi, poolAbi, FACTION, STATUS } from "@/lib/abi";
import { BEAD, MATCH_ID, POOL } from "@/lib/config";
import { useSponsoredCalls } from "@/lib/useSponsoredCalls";

const PRESETS = ["100", "250", "500"]; // pool rejects deposits below 100 BEAD

export default function TrucePool() {
  const { address, isConnected } = useAccount();
  const [amount, setAmount] = useState("100");
  const [side, setSide] = useState<number>(FACTION.HOME);
  const { send, isPending, error } = useSponsoredCalls();

  const { data: match } = useReadContract({
    address: POOL,
    abi: poolAbi,
    functionName: "getMatch",
    args: [MATCH_ID],
    query: { refetchInterval: 5000 },
  });
  const { data: affiliation } = useReadContract({
    address: POOL,
    abi: poolAbi,
    functionName: "userAffiliation",
    args: address ? [MATCH_ID, address] : undefined,
    query: { enabled: !!address },
  });

  const sideToken = match ? (affiliation === FACTION.AWAY ? match.awayToken : match.homeToken) : undefined;
  const { data: sideBalance } = useReadContract({
    address: sideToken,
    abi: factionTokenAbi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!sideToken && !!address, refetchInterval: 5000 },
  });

  if (!match) return <p className="text-white/60">Loading match...</p>;

  const home = match.totalHomeStaked;
  const away = match.totalAwayStaked;
  const total = home + away;
  const homePct = total === 0n ? 50 : Number((home * 10000n) / total) / 100;
  const status = STATUS[match.status];
  const open = status === "OPEN" && BigInt(Math.floor(Date.now() / 1000)) < match.kickoffTime;
  const locked = affiliation && affiliation !== FACTION.NONE ? affiliation : undefined;
  const activeSide = locked ?? side;

  const stake = () => {
    const wei = parseEther(amount);
    send([
      { to: BEAD, data: encodeFunctionData({ abi: beadAbi, functionName: "approve", args: [POOL, wei] }) },
      { to: POOL, data: encodeFunctionData({ abi: poolAbi, functionName: "deposit", args: [MATCH_ID, activeSide, wei] }) },
    ]);
  };

  return (
    <section className="space-y-6">
      <header className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold text-amber-300">North Red vs North White</h1>
        <span className="rounded bg-white/10 px-2 py-0.5 text-xs">{status}</span>
      </header>

      <div className="space-y-2">
        <div className="flex h-6 overflow-hidden rounded-full bg-white/10">
          <div className="bg-red-500 transition-all" style={{ width: `${homePct}%` }} />
          <div className="flex-1 bg-slate-200" />
        </div>
        <div className="flex justify-between text-xs text-white/70">
          <span>Red {formatEther(home)}</span>
          <span>White {formatEther(away)}</span>
        </div>
        <p className="text-xs text-white/50">
          {match.truceAchieved
            ? "Truce achieved."
            : "Truce bonus unlocks when the lighter side holds at least 30% of the pool."}
        </p>
        <p className="text-xs text-white/50">Truce reward pool: {formatEther(match.rewardPool)} BEAD</p>
      </div>

      {open && isConnected ? (
        <div className="space-y-3 rounded-xl border border-white/10 p-4">
          <div className="flex gap-2">
            {[
              { label: "North Red", value: FACTION.HOME },
              { label: "North White", value: FACTION.AWAY },
            ].map((s) => (
              <button
                key={s.value}
                disabled={locked !== undefined && locked !== s.value}
                onClick={() => setSide(s.value)}
                className={`flex-1 rounded-lg border py-2 text-sm disabled:opacity-30 ${
                  activeSide === s.value ? "border-amber-300 text-amber-300" : "border-white/20"
                }`}
              >
                {s.label}
              </button>
            ))}
          </div>
          {locked !== undefined && (
            <p className="text-xs text-white/50">Your side is locked for this match.</p>
          )}
          <div className="flex gap-2">
            {PRESETS.map((p) => (
              <button
                key={p}
                onClick={() => setAmount(p)}
                className={`flex-1 rounded-lg border py-2 text-sm ${amount === p ? "border-amber-300" : "border-white/20"}`}
              >
                {p}
              </button>
            ))}
          </div>
          <button
            onClick={stake}
            disabled={isPending}
            className="w-full rounded-lg bg-amber-400 py-3 font-medium text-black disabled:opacity-50"
          >
            {isPending ? "Confirm in wallet..." : `Stake ${amount} BEAD`}
          </button>
          <p className="text-xs text-white/40">1% Peace Tax goes to public goods. You receive faction tokens 1:1 on the rest.</p>
          {locked !== undefined && sideBalance !== undefined && sideBalance > 0n && (
            <button
              disabled={isPending}
              onClick={() =>
                send([
                  {
                    to: POOL,
                    data: encodeFunctionData({
                      abi: poolAbi,
                      functionName: "withdrawEarly",
                      args: [MATCH_ID, locked, sideBalance],
                    }),
                  },
                ])
              }
              className="w-full rounded-lg border border-white/20 py-2 text-sm disabled:opacity-50"
            >
              Withdraw {formatEther(sideBalance)} BEAD before kickoff
            </button>
          )}
          {error && <p className="text-xs text-red-400">{error.message}</p>}
        </div>
      ) : (
        <p className="text-sm text-white/60">
          {isConnected ? "Staking is closed for this match." : "Connect your wallet on the Home tab to stake."}
        </p>
      )}

      {isConnected && (status === "SETTLED" || status === "REFUNDED") && (
        <div className="space-y-3 rounded-xl border border-white/10 p-4">
          <p className="text-sm">
            {status === "SETTLED" ? "Settled. Claim your principal" : "Match refunded. Claim your principal"}
            {status === "SETTLED" && match.truceAchieved ? " plus the truce bonus." : "."}
          </p>
          <div className="flex gap-2">
            {[
              { label: "Claim Red", value: FACTION.HOME },
              { label: "Claim White", value: FACTION.AWAY },
            ].map((s) => (
              <button
                key={s.value}
                disabled={isPending}
                onClick={() =>
                  send([
                    {
                      to: POOL,
                      data: encodeFunctionData({
                        abi: poolAbi,
                        functionName: status === "SETTLED" ? "claimSettlement" : "claimRefund",
                        args: [MATCH_ID, s.value],
                      }),
                    },
                  ])
                }
                className="flex-1 rounded-lg bg-amber-400 py-2 text-sm font-medium text-black disabled:opacity-50"
              >
                {s.label}
              </button>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}
