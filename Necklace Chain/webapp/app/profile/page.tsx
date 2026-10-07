"use client";

import { useEffect, useState } from "react";
import { useAccount, usePublicClient, useReadContracts } from "wagmi";
import { necklaceAbi } from "@/lib/abi";
import { DEPLOY_BLOCK, NECKLACE } from "@/lib/config";

function Necklace({ tokenId }: { tokenId: bigint }) {
  const { data } = useReadContracts({
    contracts: [
      { address: NECKLACE, abi: necklaceAbi, functionName: "getRank", args: [tokenId] },
      { address: NECKLACE, abi: necklaceAbi, functionName: "getTenureCycles", args: [tokenId] },
      { address: NECKLACE, abi: necklaceAbi, functionName: "getVotingWeight", args: [tokenId] },
      { address: NECKLACE, abi: necklaceAbi, functionName: "getFeeDiscountBps", args: [tokenId] },
    ],
  });
  if (!data) return null;
  const [rank, cycles, weight, discount] = data.map((d) => d.result);
  return (
    <li className="space-y-1 rounded-xl border border-white/10 p-4 text-sm">
      <p className="font-medium text-amber-300">
        Rama Node #{tokenId.toString()} - {String(rank)}
      </p>
      <p>Tenure cycles: {String(cycles)}</p>
      <p>Voting weight: {String(weight)}x</p>
      <p>Forge fee discount: {Number(discount) / 100}%</p>
    </li>
  );
}

export default function Profile() {
  const { address, isConnected } = useAccount();
  const client = usePublicClient();
  const [tokenIds, setTokenIds] = useState<bigint[]>([]);

  useEffect(() => {
    if (!address || !client) return;
    let cancelled = false;
    (async () => {
      // The NFT is not enumerable, so rebuild holdings from Transfer logs and confirm current ownership.
      const logs = await client.getContractEvents({
        address: NECKLACE,
        abi: necklaceAbi,
        eventName: "Transfer",
        args: { to: address },
        fromBlock: DEPLOY_BLOCK,
      });
      const ids = [...new Set(logs.map((l) => l.args.tokenId as bigint))];
      const owned: bigint[] = [];
      for (const id of ids) {
        const owner = await client.readContract({ address: NECKLACE, abi: necklaceAbi, functionName: "ownerOf", args: [id] });
        if (owner.toLowerCase() === address.toLowerCase()) owned.push(id);
      }
      if (!cancelled) setTokenIds(owned);
    })().catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [address, client]);

  if (!isConnected) return <p className="text-sm text-white/60">Connect your wallet on the Home tab first.</p>;

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-semibold text-amber-300">Your Necklaces</h1>
      {tokenIds.length === 0 ? (
        <p className="text-sm text-white/60">No necklaces yet. Forge one from matching faction tokens.</p>
      ) : (
        <ul className="space-y-3">
          {tokenIds.map((id) => (
            <Necklace key={id.toString()} tokenId={id} />
          ))}
        </ul>
      )}
      <p className="text-xs text-white/40">Utilities are cosmetic and governance only. Transferring a necklace resets its tenure.</p>
    </section>
  );
}
