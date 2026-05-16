import "./globals.css";
import type { Metadata } from "next";
import Link from "next/link";
import { AuthProvider } from "@/lib/auth-context";
import { UserMenu } from "@/components/user-menu";

export const metadata: Metadata = {
  title: "Stylist — NYC personal outfit assistant",
  description:
    "Tell me where you’re going. I’ll pick what to wear from your closet using weather, occasion, and your style.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen font-sans">
        <AuthProvider>
          <header className="sticky top-0 z-20 border-b border-ink/5 bg-white/80 backdrop-blur">
            <nav className="mx-auto flex max-w-5xl items-center justify-between px-4 py-3">
              <Link href="/" className="text-base font-semibold tracking-tight">
                Stylist
                <span className="ml-1 text-accent">·</span>
                <span className="ml-1 text-xs font-normal text-ink/60">NYC</span>
              </Link>
              <div className="flex items-center gap-1 text-sm">
                <ul className="flex items-center gap-1">
                  <NavLink href="/wardrobe">Wardrobe</NavLink>
                  <NavLink href="/chat">Chat</NavLink>
                </ul>
                <UserMenu />
              </div>
            </nav>
          </header>
          <main className="mx-auto max-w-5xl px-4 py-8">{children}</main>
          <footer className="mx-auto max-w-5xl px-4 py-10 text-xs text-ink/50">
            Phase 1 build · {new Date().getFullYear()}
          </footer>
        </AuthProvider>
      </body>
    </html>
  );
}

function NavLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <li>
      <Link
        href={href}
        className="rounded-lg px-3 py-1.5 text-ink/70 transition hover:bg-ink/5 hover:text-ink"
      >
        {children}
      </Link>
    </li>
  );
}
