"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const links = [
  { href: "/", label: "Home" },
  { href: "/truce-pool", label: "Truce Pool" },
  { href: "/forge", label: "Forge" },
  { href: "/staking", label: "Tiers" },
  { href: "/profile", label: "Profile" },
];

export function Nav() {
  const path = usePathname();
  return (
    <nav className="fixed inset-x-0 bottom-0 border-t border-white/10 bg-[#0b0d17]/95 backdrop-blur">
      <ul className="mx-auto flex max-w-md justify-around py-3 text-sm">
        {links.map((l) => (
          <li key={l.href}>
            <Link href={l.href} className={path === l.href ? "text-amber-300" : "text-white/60"}>
              {l.label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
