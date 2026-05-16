"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "./auth-context";

/**
 * Redirects unauthenticated visitors to /login?next=<current-path>.
 * Returns the auth state so the caller can render `null` until `fbUser` is
 * defined (avoiding a hydration flash of authenticated UI).
 */
export function useRequireAuth() {
  const auth = useAuth();
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (auth.fbUser === null) {
      const next = encodeURIComponent(pathname || "/");
      router.replace(`/login?next=${next}`);
    }
  }, [auth.fbUser, pathname, router]);

  return auth;
}
