"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  isSignInWithEmailLink,
  sendSignInLinkToEmail,
  signInWithEmailLink,
  signInWithPopup,
} from "firebase/auth";
import { Mail, ArrowRight } from "lucide-react";
import { firebaseAuth, firebaseConfigured, googleProvider } from "@/lib/firebase";
import { useAuth } from "@/lib/auth-context";

const EMAIL_KEY = "stylist.signin.email";

export default function LoginPage() {
  // useSearchParams() must be inside a Suspense boundary for Next.js 14
  // static generation. See https://nextjs.org/docs/messages/missing-suspense-with-csr-bailout
  return (
    <Suspense fallback={null}>
      <LoginInner />
    </Suspense>
  );
}

function LoginInner() {
  const router = useRouter();
  const params = useSearchParams();
  const { fbUser } = useAuth();
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  // If a magic link brought us here, complete the sign-in.
  useEffect(() => {
    if (!firebaseConfigured()) return;
    const auth = firebaseAuth();
    if (typeof window === "undefined") return;
    if (!isSignInWithEmailLink(auth, window.location.href)) return;
    let stored = window.localStorage.getItem(EMAIL_KEY);
    if (!stored) {
      stored = window.prompt("Confirm the email you used to sign in:") ?? "";
    }
    if (!stored) return;
    setBusy(true);
    signInWithEmailLink(auth, stored, window.location.href)
      .then(() => {
        window.localStorage.removeItem(EMAIL_KEY);
        router.replace(params.get("next") ?? "/wardrobe");
      })
      .catch((e) => setErr(String(e?.message ?? e)))
      .finally(() => setBusy(false));
  }, [params, router]);

  // Already signed in? Bounce to the requested page.
  useEffect(() => {
    if (fbUser) router.replace(params.get("next") ?? "/wardrobe");
  }, [fbUser, params, router]);

  async function emailLink() {
    if (!firebaseConfigured()) {
      setErr("Firebase not configured for this build.");
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      await sendSignInLinkToEmail(firebaseAuth(), email, {
        url: window.location.origin + "/login",
        handleCodeInApp: true,
      });
      window.localStorage.setItem(EMAIL_KEY, email);
      setSent(true);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function google() {
    if (!firebaseConfigured()) {
      setErr("Firebase not configured for this build.");
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      await signInWithPopup(firebaseAuth(), googleProvider);
      router.replace(params.get("next") ?? "/wardrobe");
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="mx-auto max-w-md space-y-6">
      <header>
        <h1 className="text-3xl font-semibold tracking-tight">Sign in</h1>
        <p className="mt-2 text-sm text-ink/60">
          One step. We’ll email you a magic link — no password to remember.
        </p>
      </header>

      <div className="card space-y-4">
        <button onClick={google} disabled={busy} className="btn-secondary w-full">
          <GoogleGlyph /> Continue with Google
        </button>
        <div className="flex items-center gap-3 text-xs text-ink/40">
          <span className="h-px flex-1 bg-ink/10" />
          OR
          <span className="h-px flex-1 bg-ink/10" />
        </div>
        {sent ? (
          <p className="rounded-xl bg-accent/10 p-3 text-sm text-ink/80">
            Magic link sent to <strong>{email}</strong>. Open it on this device to
            finish signing in.
          </p>
        ) : (
          <>
            <label className="block text-sm font-medium">Email</label>
            <input
              className="input"
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
            <button
              onClick={emailLink}
              disabled={busy || !email.includes("@")}
              className="btn-primary w-full"
            >
              <Mail className="h-4 w-4" /> Send magic link <ArrowRight className="h-4 w-4" />
            </button>
          </>
        )}
        {err && <p className="text-sm text-red-600">{err}</p>}
      </div>

      <p className="text-center text-xs text-ink/50">
        By continuing you agree this is a prototype and your data may be wiped
        between phases.
      </p>
    </section>
  );
}

function GoogleGlyph() {
  return (
    <svg viewBox="0 0 18 18" className="h-4 w-4" aria-hidden>
      <path
        d="M17.64 9.2c0-.64-.06-1.25-.17-1.84H9v3.48h4.84a4.14 4.14 0 01-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62z"
        fill="#4285F4"
      />
      <path
        d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.81.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 009 18z"
        fill="#34A853"
      />
      <path
        d="M3.97 10.72A5.4 5.4 0 013.68 9c0-.6.1-1.18.29-1.72V4.95H.96A9 9 0 000 9c0 1.45.35 2.83.96 4.05l3.01-2.33z"
        fill="#FBBC05"
      />
      <path
        d="M9 3.58c1.32 0 2.5.45 3.44 1.34l2.58-2.58C13.46.9 11.43 0 9 0A9 9 0 00.96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58z"
        fill="#EA4335"
      />
    </svg>
  );
}
