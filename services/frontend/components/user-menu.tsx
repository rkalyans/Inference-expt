"use client";

import Link from "next/link";
import { LogIn, LogOut, User as UserIcon } from "lucide-react";
import { useAuth } from "@/lib/auth-context";

export function UserMenu() {
  const { fbUser, profile, signOut } = useAuth();

  if (fbUser === undefined) {
    return <span className="ml-2 text-xs text-ink/40">…</span>;
  }
  if (fbUser === null) {
    return (
      <Link href="/login" className="ml-2 btn-secondary !py-1.5">
        <LogIn className="h-4 w-4" /> Sign in
      </Link>
    );
  }
  return (
    <div className="ml-2 flex items-center gap-2 text-xs">
      <span className="inline-flex items-center gap-1.5 rounded-full bg-ink/5 px-2.5 py-1">
        <UserIcon className="h-3.5 w-3.5" />
        {profile?.email ?? fbUser.email}
      </span>
      <button
        onClick={signOut}
        className="rounded-lg p-1.5 text-ink/60 hover:bg-ink/5 hover:text-ink"
        aria-label="Sign out"
        title="Sign out"
      >
        <LogOut className="h-4 w-4" />
      </button>
    </div>
  );
}
