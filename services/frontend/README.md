# frontend — Stylist web app

Next.js 14 (App Router) + TypeScript + Tailwind. Deployed to Cloud Run at
`app-<env>.quantum-23.com` (prod: `app.quantum-23.com`).

## Local dev

```bash
cd services/frontend
npm install
NEXT_PUBLIC_AGENT_URL=https://api-dev.quantum-23.com npm run dev
```

Open <http://localhost:3000>.

## Architecture

The frontend talks **only** to the agent-orchestrator (`api-<env>.quantum-23.com`).
The agent fronts the private inventory + weather services through its `/api`
BFF router. This keeps the public attack surface to a single service.

```
Browser
  └── (HTTPS) → stylist-<env>-agent (public)
                  ├── /chat       → agent runtime (SSE)
                  ├── /api/users  → inventory (private, OIDC)
                  └── /api/items  → inventory (private, OIDC)
```

## Pages

| Route | Purpose |
|---|---|
| `/` | Landing |
| `/onboarding` | 3-step wizard (email → style → NYC zone). Calls `POST /api/users`. |
| `/wardrobe` | List + add + delete clothing items. Uploads use signed PUT URLs minted by inventory. |
| `/chat` | SSE streaming chat. Renders thought / tool_call / tool_result / final / saved events live. |

## Auth (Phase 1.4 only)

Phase 1.4 uses a `localStorage`-backed pseudo-auth (just stores the user id
returned by the inventory service). Phase 1.5 swaps in Firebase Auth and
extracts the user id from a verified JWT.

## Production build

```bash
docker build --build-arg NEXT_PUBLIC_AGENT_URL=https://api-dev.quantum-23.com -t frontend:dev .
docker run --rm -p 8080:8080 frontend:dev
```

The Dockerfile uses Next.js `output: "standalone"` so the runtime image is
small (~200MB) and contains only the bundled server.
