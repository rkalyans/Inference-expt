"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import {
  streamChat,
  type ChatEvent,
  type Recommendation,
  type Zone,
} from "@/lib/api";
import { useRequireAuth } from "@/lib/use-require-auth";
import { Send, Sparkles, Shirt, Wrench, Cloud } from "lucide-react";

const ZONES: Zone[] = ["midtown", "waterfront", "downtown", "uptown"];

type Msg =
  | { role: "user"; text: string }
  | { role: "assistant"; events: ChatEvent[]; rec?: Recommendation; text?: string };

export default function ChatPage() {
  const { fbUser, getToken } = useRequireAuth();
  const [zone, setZone] = useState<Zone>("midtown");
  const [input, setInput] = useState("");
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [busy, setBusy] = useState(false);
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => () => abortRef.current?.abort(), []);

  if (fbUser === undefined || fbUser === null) {
    return <p className="text-sm text-ink/60">Loading…</p>;
  }

  async function send() {
    const text = input.trim();
    if (!text || busy) return;
    setInput("");
    setMsgs((s) => [...s, { role: "user", text }, { role: "assistant", events: [] }]);
    setBusy(true);
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    try {
      for await (const ev of streamChat(
        { query: text, zone },
        getToken,
        { signal: ctrl.signal },
      )) {
        setMsgs((s) => {
          const last = s[s.length - 1];
          if (last.role !== "assistant") return s;
          const next: Msg = {
            ...last,
            events: [...last.events, ev],
            rec:
              ev.event === "final" && "recommendation" in ev
                ? ev.recommendation
                : last.rec,
            text:
              ev.event === "final" && "text" in ev && typeof ev.text === "string"
                ? ev.text
                : last.text,
          };
          return [...s.slice(0, -1), next];
        });
      }
    } catch (e) {
      setMsgs((s) => {
        const last = s[s.length - 1];
        if (last.role !== "assistant") return s;
        const err: ChatEvent = { event: "error", error: String(e) };
        return [...s.slice(0, -1), { ...last, events: [...last.events, err] }];
      });
    } finally {
      setBusy(false);
      abortRef.current = null;
    }
  }

  return (
    <section className="space-y-4">
      <header>
        <h1 className="text-3xl font-semibold tracking-tight">Chat</h1>
        <p className="mt-1 text-sm text-ink/60">
          Ask what to wear. Stylist will pull from your wardrobe and current weather.
        </p>
      </header>

      <div className="space-y-3">
        {msgs.map((m, i) =>
          m.role === "user" ? (
            <div key={i} className="card ml-auto max-w-md bg-ink text-white">
              {m.text}
            </div>
          ) : (
            <AssistantBubble key={i} m={m} />
          ),
        )}
        {msgs.length === 0 && (
          <div className="card text-sm text-ink/60">
            Try: <em>“What should I wear to a 7pm rooftop dinner downtown?”</em>
          </div>
        )}
      </div>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          send();
        }}
        className="sticky bottom-4 flex items-end gap-2 rounded-2xl bg-white p-2 shadow-md ring-1 ring-ink/5"
      >
        <select
          value={zone}
          onChange={(e) => setZone(e.target.value as Zone)}
          className="input max-w-[8.5rem] capitalize"
        >
          {ZONES.map((z) => (
            <option key={z} value={z}>
              {z}
            </option>
          ))}
        </select>
        <textarea
          className="input min-h-[44px] flex-1 resize-none"
          placeholder="Ask Stylist…"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send();
            }
          }}
          rows={1}
        />
        <button className="btn-primary" disabled={busy || !input.trim()} type="submit">
          <Send className="h-4 w-4" /> {busy ? "Thinking…" : "Send"}
        </button>
      </form>
    </section>
  );
}

function AssistantBubble({ m }: { m: Extract<Msg, { role: "assistant" }> }) {
  return (
    <div className="card max-w-2xl space-y-3">
      <ol className="space-y-1 text-xs text-ink/60">
        {m.events
          .filter((e) => e.event === "thought" || e.event === "tool_call" || e.event === "tool_result")
          .map((e, i) => (
            <li key={i} className="flex items-start gap-2">
              {e.event === "tool_call" ? (
                <Wrench className="mt-0.5 h-3.5 w-3.5 text-accent" />
              ) : e.event === "tool_result" ? (
                <Cloud className="mt-0.5 h-3.5 w-3.5 text-accent" />
              ) : (
                <Sparkles className="mt-0.5 h-3.5 w-3.5 text-accent" />
              )}
              <span>
                {e.event === "thought"
                  ? (e as { text: string }).text
                  : `${e.event === "tool_call" ? "calling" : "got"} ${(e as { name: string }).name}`}
              </span>
            </li>
          ))}
      </ol>

      {m.rec && (
        <>
          <p className="text-sm">{m.rec.rationale}</p>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            {m.rec.items.map((it) => (
              <article key={it.id} className="rounded-xl bg-ink/5 p-3">
                <div className="relative h-24 w-full overflow-hidden rounded-lg bg-white">
                  {it.photo_url ? (
                    <Image src={it.photo_url} alt={it.name} fill className="object-cover" />
                  ) : (
                    <div className="grid h-full w-full place-items-center text-ink/30">
                      <Shirt className="h-7 w-7" />
                    </div>
                  )}
                </div>
                <div className="mt-2 text-xs font-medium">{it.name}</div>
                <div className="text-[10px] uppercase tracking-wide text-ink/50">{it.category}</div>
              </article>
            ))}
          </div>
        </>
      )}

      {!m.rec && m.text && <p className="text-sm">{m.text}</p>}

      {m.events.some((e) => e.event === "error") && (
        <p className="text-sm text-red-600">
          {(m.events.find((e) => e.event === "error") as { error?: string; text?: string }).error ??
            (m.events.find((e) => e.event === "error") as { text?: string }).text}
        </p>
      )}
    </div>
  );
}
