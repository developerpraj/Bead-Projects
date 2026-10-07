import { createConfig, http } from "wagmi";
import { base, baseSepolia } from "wagmi/chains";
import { coinbaseWallet } from "wagmi/connectors";

const zero = "0x0000000000000000000000000000000000000000" as const;
const addr = (v: string | undefined) => (v && v.startsWith("0x") ? (v as `0x${string}`) : zero);

export const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 84532);
export const chain = CHAIN_ID === base.id ? base : baseSepolia;

export const BEAD = addr(process.env.NEXT_PUBLIC_BEAD_ADDRESS);
export const POOL = addr(process.env.NEXT_PUBLIC_POOL_ADDRESS);
export const NECKLACE = addr(process.env.NEXT_PUBLIC_NECKLACE_ADDRESS);
export const STAKING = addr(process.env.NEXT_PUBLIC_STAKING_ADDRESS);
export const PAYMASTER = addr(process.env.NEXT_PUBLIC_PAYMASTER_ADDRESS);

export const MATCH_ID = BigInt(process.env.NEXT_PUBLIC_MATCH_ID ?? "1");
export const DEPLOY_BLOCK = BigInt(process.env.NEXT_PUBLIC_DEPLOY_BLOCK ?? "0");
export const PAYMASTER_URL = process.env.NEXT_PUBLIC_PAYMASTER_URL || undefined;

export const wagmiConfig = createConfig({
  chains: [chain],
  connectors: [coinbaseWallet({ appName: "Necklace Chain", preference: { options: "smartWalletOnly" } })],
  transports: {
    [base.id]: http(process.env.NEXT_PUBLIC_RPC_URL),
    [baseSepolia.id]: http(process.env.NEXT_PUBLIC_RPC_URL),
  },
  ssr: true,
});
