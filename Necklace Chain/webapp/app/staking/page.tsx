"use client";

import { useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { encodeFunctionData, formatEther, parseEther } from "viem";
import { beadAbi, stakingAbi } from "@/lib/abi";
import { BEAD, STAKING } from "@/lib/config";
import { useSponsoredCalls } from "@/lib/useSponsoredCalls";

const TIERS = [
  { name: "The Chai", amount: "18", blurb: "Basic participation and polls." },
  { name: "The Chotki", amount: "33", blurb: "Can challenge an oracle result. A rejected challenge slashes 33 BEAD to public goods." },
  { name: "The Master Council", amount: "99", blurb: "One vote on match whitelisting and dispute escalation. 99 seats." },
];
const TIER_NAMES = ["No tier", "Chai", "Chotki", "Master Council"];

export default function Staking() {
  const { address, isConnected } = useAccount();
  const [amount, setAmount] = useState("18");
  const { send, isPending, error } = useSponsoredCalls();

  const enabled = { enabled: !!address, refetchInterval: 5000 };
  const { data: staked } = useReadContract({
    address: STAKING,
    abi: stakingAbi,
    functionName: "stakeOf",
    args: address ? [address] : undefined,
    query: enabled,
  });
  const { data: tier } = useReadContract({
    address: STAKING,
    abi: stakingAbi,
    functionName: "tierOf",
    args: address ? [address] : undefined,
    query: enabled,
  });
  const { data: locked } = useReadContract({
    address: STAKING,
    abi: stakingAbi,
    functionName: "bondLocked",
    args: address ? [address] : undefined,
    query: enabled,
  });
  const { data: seats } = useReadContract({
    address: STAKING,
    abi: stakingAbi,
    functionName: "councilCount",
    query: { refetchInterval: 15000 },
  });

  if (!isConnected) return <p className="text-sm text-white/60">Connect your wallet on the Home tab first.</p>;

  const stake = () => {
    const wei = parseEther(amount);
    send([
      { to: BEAD, data: encodeFunctionData({ abi: beadAbi, functionName: "approve", args: [STAKING, wei] }) },
      { to: STAKING, data: encodeFunctionData({ abi: stakingAbi, functionName: "stake", args: [wei] }) },
    ]);
  };
  const unstakeAll = () => {
    if (!staked) return;
    send([{ to: STAKING, data: encodeFunctionData({ abi: stakingAbi, functionName: "unstake", args: [staked] }) }]);
  };

  return (
    <section className="space-y-5">
      <header>
        <h1 className="text-xl font-semibold text-amber-300">Governance tiers</h1>
        <p className="text-sm text-white/60">
          Staked: {staked !== undefined ? formatEther(staked) : "..."} BEAD ({tier !== undefined ? TIER_NAMES[tier] : "..."}).
          Council seats taken: {seats !== undefined ? seats.toString() : "..."} / 99.
        </p>
      </header>

      <ul className="space-y-2">
        {TIERS.map((t) => (
          <li key={t.name}>
            <button
              onClick={() => setAmount(t.amount)}
              className={`w-full rounded-xl border p-3 text-left text-sm ${amount === t.amount ? "border-amber-300" : "border-white/10"}`}
            >
              <span className="font-medium">
                {t.name} - {t.amount} BEAD
              </span>
              <span className="block text-xs text-white/50">{t.blurb}</span>
            </button>
          </li>
        ))}
      </ul>

      <div className="space-y-3 rounded-xl border border-white/10 p-4">
        <button
          onClick={stake}
          disabled={isPending}
          className="w-full rounded-lg bg-amber-400 py-3 font-medium text-black disabled:opacity-50"
        >
          {isPending ? "Confirm in wallet..." : `Stake ${amount} BEAD`}
        </button>
        <button
          onClick={unstakeAll}
          disabled={isPending || !staked || locked === true}
          className="w-full rounded-lg border border-white/20 py-2 text-sm disabled:opacity-40"
        >
          Unstake everything
        </button>
        {locked === true && <p className="text-xs text-amber-300">Your stake is locked while an oracle challenge is open.</p>}
        {error && <p className="text-xs text-red-400">{error.message}</p>}
      </div>

      <p className="text-xs text-white/40">
        Tiers set voting and dispute rights only. Staking pays no yield, and the council has no say over treasury funds.
      </p>
    </section>
  );
}
