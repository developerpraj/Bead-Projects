"use client";

import { useEffect, useState } from "react";

/** Returns the Telegram first name when running inside Telegram, otherwise null. */
export function useTelegramUser(): string | null {
  const [name, setName] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const { init, retrieveLaunchParams } = await import("@telegram-apps/sdk");
        init();
        const params = retrieveLaunchParams();
        const first = params.tgWebAppData?.user?.first_name ?? null;
        if (!cancelled) setName(first);
      } catch {
        // Not launched from Telegram (plain browser): stay anonymous.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return name;
}

/** Opens this app in the phone's default browser, where passkeys are fully supported. */
export async function openInExternalBrowser(): Promise<void> {
  const url = window.location.origin;
  try {
    const { openLink } = await import("@telegram-apps/sdk");
    if (openLink.isAvailable()) {
      openLink(url);
      return;
    }
  } catch {
    // Fall through to a plain window.open.
  }
  window.open(url, "_blank", "noopener,noreferrer");
}
