"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  onAuthStateChanged,
  onIdTokenChanged,
  signOut as fbSignOut,
  type User,
} from "firebase/auth";
import { firebaseAuth, firebaseConfigured } from "./firebase";

type Profile = { id: string; email: string };

type AuthState = {
  /** Firebase user object — null when signed out, undefined while loading. */
  fbUser: User | null | undefined;
  /** Inventory user as returned by /api/users/me. Provisioned on first call. */
  profile: Profile | null;
  /** Convenience: returns a fresh ID token (or null if signed out). */
  getToken: () => Promise<string | null>;
  signOut: () => Promise<void>;
};

const Ctx = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [fbUser, setFbUser] = useState<User | null | undefined>(undefined);
  const [profile, setProfile] = useState<Profile | null>(null);

  useEffect(() => {
    if (!firebaseConfigured()) {
      setFbUser(null);
      return;
    }
    const auth = firebaseAuth();
    const unsub1 = onAuthStateChanged(auth, (u) => setFbUser(u));
    // Token refresh keeps the cached profile attached to the latest user.
    const unsub2 = onIdTokenChanged(auth, async (u) => {
      if (!u) {
        setProfile(null);
        return;
      }
    });
    return () => {
      unsub1();
      unsub2();
    };
  }, []);

  // Fetch the inventory profile on sign-in. Lazy-creates on the backend.
  useEffect(() => {
    if (!fbUser) {
      setProfile(null);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const token = await fbUser.getIdToken();
        const r = await fetch(
          `${process.env.NEXT_PUBLIC_AGENT_URL ?? ""}/api/users/me`,
          { headers: { Authorization: `Bearer ${token}` } },
        );
        if (!r.ok) throw new Error(`me: ${r.status}`);
        const data = (await r.json()) as Profile;
        if (!cancelled) setProfile(data);
      } catch (err) {
        // Fail loud in dev, soft in prod.
        // eslint-disable-next-line no-console
        console.warn("auth.profile_fetch_failed", err);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [fbUser]);

  const value = useMemo<AuthState>(
    () => ({
      fbUser,
      profile,
      getToken: async () => (fbUser ? await fbUser.getIdToken() : null),
      signOut: async () => {
        if (firebaseConfigured()) await fbSignOut(firebaseAuth());
      },
    }),
    [fbUser, profile],
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAuth(): AuthState {
  const v = useContext(Ctx);
  if (!v) throw new Error("useAuth must be used inside <AuthProvider>");
  return v;
}
