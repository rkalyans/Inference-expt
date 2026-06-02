// Typed client for the agent-orchestrator BFF + chat SSE.
//
// Every request carries a Firebase ID token as `Authorization: Bearer ...`.
// The token getter is passed in by the caller (usually wired to
// `useAuth().getToken`) so this module stays unaware of Firebase.

export const AGENT_URL =
  (typeof process !== "undefined" && process.env.NEXT_PUBLIC_AGENT_URL) || "";

export type TokenGetter = () => Promise<string | null>;

export type Category = "top" | "bottom" | "footwear" | "outerwear" | "accessory";
export type Zone = "midtown" | "waterfront" | "downtown" | "uptown";

export type Item = {
  id: string;
  user_id: string;
  name: string;
  category: Category;
  attributes: Record<string, unknown>;
  photo_url: string | null;
  created_at: string;
};

export type User = {
  id: string;
  email: string;
  preferences: Record<string, unknown>;
  created_at: string;
};

async function req<T>(
  path: string,
  getToken: TokenGetter,
  init?: RequestInit,
): Promise<T> {
  const token = await getToken();
  if (!token) throw new Error("not signed in");
  const url = `${AGENT_URL}${path}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      "content-type": "application/json",
      Authorization: `Bearer ${token}`,
      ...(init?.headers ?? {}),
    },
  });
  if (!res.ok) {
    let msg = `${res.status} ${res.statusText}`;
    try {
      msg += " - " + (await res.text());
    } catch {}
    throw new Error(msg);
  }
  if (res.status === 204) return undefined as unknown as T;
  return (await res.json()) as T;
}

export function makeApi(getToken: TokenGetter) {
  return {
    me() {
      return req<{ id: string; email: string }>("/api/users/me", getToken);
    },
    updatePreferences(preferences: Record<string, unknown>) {
      return req<User>("/api/users/me/preferences", getToken, {
        method: "PUT",
        body: JSON.stringify({ preferences }),
      });
    },
    listItems(category?: Category) {
      const q = new URLSearchParams({ limit: "200" });
      if (category) q.set("category", category);
      return req<{ items: Item[] }>(`/api/items?${q.toString()}`, getToken);
    },
    createItem(body: {
      name: string;
      category: Category;
      attributes?: Record<string, unknown>;
      photo_url?: string | null;
    }) {
      return req<Item>(`/api/items`, getToken, {
        method: "POST",
        body: JSON.stringify(body),
      });
    },
    deleteItem(item_id: string) {
      return req<void>(`/api/items/${item_id}`, getToken, { method: "DELETE" });
    },
    mintUploadUrl(content_type = "image/jpeg") {
      return req<{
        upload_url: string;
        object_uri: string;
        expires_in_seconds: number;
      }>(`/api/items/upload-url`, getToken, {
        method: "POST",
        body: JSON.stringify({ content_type }),
      });
    },
  };
}
export type Api = ReturnType<typeof makeApi>;

// ---- /chat SSE ----

export type ChatEvent =
  | { event: "thought"; text: string }
  | { event: "tool_call"; name: string; args: unknown }
  | { event: "tool_result"; name: string; result: unknown }
  | { event: "final"; text?: string; recommendation?: Recommendation }
  | { event: "saved"; recommendation_id: string }
  | { event: "error"; error?: string; text?: string };

export type Recommendation = {
  rationale: string;
  items: Item[];
  weather?: unknown;
};

export async function* streamChat(
  body: { query: string; zone: Zone },
  getToken: TokenGetter,
  opts: { signal?: AbortSignal } = {},
): AsyncGenerator<ChatEvent> {
  const token = await getToken();
  if (!token) throw new Error("not signed in");
  const res = await fetch(`${AGENT_URL}/chat`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
    signal: opts.signal,
  });
  if (!res.ok || !res.body) {
    throw new Error(`chat failed: ${res.status} ${res.statusText}`);
  }
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    // Normalize CRLF -> LF: sse_starlette emits `\r\n` line separators, so
    // frames are delimited by `\r\n\r\n`. The framing logic below splits on
    // `\n\n`, which never matches inside `\r\n\r\n`. Normalize here so the
    // parser works regardless of the server's separator choice.
    buf += decoder.decode(value, { stream: true }).replace(/\r\n?/g, "\n");
    // SSE frames are separated by blank lines
    let idx: number;
    while ((idx = buf.indexOf("\n\n")) >= 0) {
      const frame = buf.slice(0, idx);
      buf = buf.slice(idx + 2);
      const dataLine = frame
        .split("\n")
        .find((l) => l.startsWith("data:"));
      if (!dataLine) continue;
      const json = dataLine.slice(5).trim();
      try {
        yield JSON.parse(json) as ChatEvent;
      } catch {
        // ignore malformed frames
      }
    }
  }
}
