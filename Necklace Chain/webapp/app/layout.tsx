import type { Metadata, Viewport } from "next";
import "./globals.css";
import { Providers } from "./providers";
import { Nav } from "@/components/Nav";

export const metadata: Metadata = {
  title: "Necklace Chain",
  description: "Cosmic Protocol truce pool",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen pb-20">
        <Providers>
          <main className="mx-auto max-w-md px-4 py-6">{children}</main>
          <Nav />
        </Providers>
      </body>
    </html>
  );
}
