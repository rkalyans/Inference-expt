"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { makeApi } from "@/lib/api";
import { useRequireAuth } from "@/lib/use-require-auth";
import { ArrowRight, Check } from "lucide-react";

const STYLES = [
  "minimal",
  "smart-casual",
  "streetwear",
  "preppy",
  "athleisure",
  "vintage",
] as const;

const ZONES = ["midtown", "waterfront", "downtown", "uptown"] as const;

export default function OnboardingPage() {
  const router = useRouter();
  const { fbUser, getToken } = useRequireAuth();
  const api = useMemo(() => makeApi(getToken), [getToken]);

  const [step, setStep] = useState(1);
  const [style, setStyle] = useState<(typeof STYLES)[number]>("smart-casual");
  const [zone, setZone] = useState<(typeof ZONES)[number]>("midtown");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  if (fbUser === undefined || fbUser === null) {
    return <p className="text-sm text-ink/60">Loading…</p>;
  }

  async function finish() {
    setBusy(true);
    setErr(null);
    try {
      await api.updatePreferences({ style, default_zone: zone });
      router.push("/wardrobe");
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="mx-auto max-w-xl space-y-6">
      <header>
        <h1 className="text-3xl font-semibold tracking-tight">Welcome</h1>
        <p className="mt-2 text-sm text-ink/60">A few quick questions and you’re in.</p>
      </header>

      <ol className="flex items-center gap-2 text-xs text-ink/60">
        {[1, 2].map((n) => (
          <li
            key={n}
            className={`flex h-6 w-6 items-center justify-center rounded-full text-[11px] ${
              step >= n ? "bg-ink text-white" : "bg-ink/10"
            }`}
          >
            {step > n ? <Check className="h-3 w-3" /> : n}
          </li>
        ))}
      </ol>

      {step === 1 && (
        <div className="card space-y-4">
          <div className="text-sm font-medium">Your style</div>
          <div className="flex flex-wrap gap-2">
            {STYLES.map((s) => (
              <button
                key={s}
                onClick={() => setStyle(s)}
                className={`rounded-xl border px-3 py-1.5 text-sm capitalize ${
                  style === s ? "border-ink bg-ink text-white" : "border-ink/15 bg-white"
                }`}
              >
                {s.replace("-", " ")}
              </button>
            ))}
          </div>
          <div className="flex gap-3">
            <button onClick={() => setStep(2)} className="btn-primary">
              Continue <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      )}

      {step === 2 && (
        <div className="card space-y-4">
          <div className="text-sm font-medium">Where in NYC do you spend most days?</div>
          <div className="grid grid-cols-2 gap-2">
            {ZONES.map((z) => (
              <button
                key={z}
                onClick={() => setZone(z)}
                className={`rounded-xl border px-3 py-2 text-sm capitalize ${
                  zone === z ? "border-ink bg-ink text-white" : "border-ink/15 bg-white"
                }`}
              >
                {z}
              </button>
            ))}
          </div>
          {err && <p className="text-sm text-red-600">{err}</p>}
          <div className="flex gap-3">
            <button onClick={() => setStep(1)} className="btn-secondary">
              Back
            </button>
            <button onClick={finish} disabled={busy} className="btn-primary">
              {busy ? "Saving…" : "Finish"} <Check className="h-4 w-4" />
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
