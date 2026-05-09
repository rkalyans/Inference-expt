# NYC Weather-Based Clothing Recommender — Agentic Architecture
## Deep Agents + Open-Weight Models + GCP

---

## Why Deep Agents Are a Better Fit Here

### Current Architecture (Rigid Pipeline)
```
Weather → Rules → Filter → Score → Rank → Output
         (fixed order, always runs everything)
```

### Agentic Architecture (Adaptive Reasoning)
```
User Request → Planner Agent → Decides what's needed → Spawns subagents → Synthesizes
              (dynamic, skips unnecessary steps, reasons about edge cases)
```

### Key Advantages for This System

| Problem with Rigid Pipeline | Deep Agents Solution |
|---|---|
| Always runs ALL services even for simple queries | Agent **plans** and only invokes what's needed |
| Fixed scoring formula can't handle nuance | Agent **reasons** about edge cases ("rooftop at 10pm by water = dress warm despite 70°F day") |
| Can't explain its recommendations naturally | Agent produces **natural language rationale** alongside picks |
| Memory is just a vector update | Agent has **long-term memory** that persists context across sessions |
| No adaptation to ambiguous inputs | Agent can **ask clarifying questions** via human-in-the-loop |
| Street feed always runs on schedule | Agent **decides** if street data is needed for this particular request |
| Outfit combination is brute-force | Agent **reasons** about combinations like a human stylist |

---

## 1. High-Level Agentic Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              CLIENT LAYER                                        │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                     React SPA (Next.js on Cloud Run)                       │  │
│  │                                                                           │  │
│  │  ┌────────────┐  ┌────────────┐  ┌──────────────┐  ┌─────────────────┐  │  │
│  │  │  Inventory │  │  Chat /    │  │   Location   │  │   Timeframe     │  │  │
│  │  │  Manager   │  │  Request   │  │   Picker     │  │   Selector      │  │  │
│  │  │            │  │  Interface │  │              │  │                 │  │  │
│  │  └────────────┘  └────────────┘  └──────────────┘  └─────────────────┘  │  │
│  │                                                                           │  │
│  │  ┌────────────────────────────┐  ┌────────────────────────────────────┐  │  │
│  │  │   Outfit Recommendation    │  │       History & Feedback           │  │  │
│  │  │   + Agent Reasoning View   │  │           Dashboard                │  │  │
│  │  └────────────────────────────┘  └────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       API GATEWAY (Cloud Endpoints)                              │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    DEEP AGENT ORCHESTRATION LAYER (Cloud Run)                    │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                           │  │
│  │                     ┌─────────────────────────┐                           │  │
│  │                     │   STYLIST AGENT (Root)   │                           │  │
│  │                     │   (Mistral-7B / Llama-3) │                           │  │
│  │                     │                         │                           │  │
│  │                     │   • Plans approach       │                           │  │
│  │                     │   • Spawns subagents     │                           │  │
│  │                     │   • Synthesizes final    │                           │  │
│  │                     │     recommendation       │                           │  │
│  │                     │   • Manages memory       │                           │  │
│  │                     └────────────┬────────────┘                           │  │
│  │                                  │                                        │  │
│  │              ┌───────────────────┼───────────────────┐                    │  │
│  │              │                   │                   │                    │  │
│  │              ▼                   ▼                   ▼                    │  │
│  │  ┌──────────────────┐ ┌─────────────────┐ ┌──────────────────────┐      │  │
│  │  │  WEATHER AGENT   │ │  STREET SCOUT   │ │  WARDROBE AGENT      │      │  │
│  │  │  (Subagent)      │ │  AGENT          │ │  (Subagent)          │      │  │
│  │  │                  │ │  (Subagent)     │ │                      │      │  │
│  │  │  • Fetch forecast│ │                 │ │  • Search inventory  │      │  │
│  │  │  • Apply micro-  │ │  • Analyze feed │ │  • Score items       │      │  │
│  │  │    climate adj.  │ │  • Detect trends│ │  • Build combos      │      │  │
│  │  │  • Summarize     │ │  • Summarize    │ │  • Identify gaps     │      │  │
│  │  │    conditions    │ │    what people  │ │                      │      │  │
│  │  │                  │ │    are wearing  │ │                      │      │  │
│  │  └──────────────────┘ └─────────────────┘ └──────────────────────┘      │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  TOOLS (available to all agents)                                     │  │  │
│  │  │                                                                     │  │  │
│  │  │  • get_weather(location, timeframe)                                 │  │  │
│  │  │  • search_inventory(query, filters)                                 │  │  │
│  │  │  • get_street_trends(zone, time)                                    │  │  │
│  │  │  • compute_similarity(item_embed, target_embed)                     │  │  │
│  │  │  • get_user_history(user_id, context)                               │  │  │
│  │  │  • suggest_purchase(gap_description)                                │  │  │
│  │  │  • rate_outfit_coherence(items[])                                   │  │  │
│  │  │  • describe_clothing_image(image_url)                               │  │  │
│  │  │  • save_recommendation(user_id, recommendation)                     │  │  │
│  │  │  • ask_user(question)  ← human-in-the-loop                         │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  FILESYSTEM BACKEND (Working Memory)                                 │  │  │
│  │  │                                                                     │  │  │
│  │  │  /session/{id}/plan.md          — current task plan                 │  │  │
│  │  │  /session/{id}/weather.json     — fetched weather data              │  │  │
│  │  │  /session/{id}/candidates.json  — candidate outfits                 │  │  │
│  │  │  /session/{id}/trends.json      — street trend data                 │  │  │
│  │  │  /session/{id}/reasoning.md     — agent's reasoning trace           │  │  │
│  │  │  /memory/{user_id}/prefs.json   — long-term preferences            │  │  │
│  │  │  /memory/{user_id}/history.json — past selections + ratings         │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    AI/ML INFERENCE LAYER (GKE + GPUs)                            │
│                         (Same as before — models serve as tools)                 │
│                                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐  │
│  │  vLLM             │  │  vLLM             │  │  Triton Inference Server     │  │
│  │  Mistral-7B       │  │  LLaVA-NeXT-13B   │  │  YOLOv8 + SAM-2 + CLIP     │  │
│  │  (Agent Brain)    │  │  (Vision Tasks)   │  │  + FashionCLIP              │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────────────────┘  │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Qdrant Vector DB — clothing embeddings, preferences, trends              │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              DATA LAYER (GCP)                                    │
│  Cloud SQL │ Firestore │ BigQuery │ Cloud Storage │ Memorystore (Redis)          │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Agent Design — Deep Agents Implementation

### 2.1 Root Agent: The Stylist

```python
from deepagents import create_deep_agent

stylist_agent = create_deep_agent(
    model="ollama:mistral-7b-instruct",  # Self-hosted via vLLM/Ollama
    tools=[
        get_weather,
        search_inventory,
        get_street_trends,
        compute_similarity,
        get_user_history,
        suggest_purchase,
        rate_outfit_coherence,
        describe_clothing_image,
        save_recommendation,
        ask_user,  # human-in-the-loop
    ],
    system_prompt=STYLIST_SYSTEM_PROMPT,
    memory_store=firestore_memory,     # Long-term memory backend
    filesystem_backend=gcs_backend,    # Cloud Storage for working files
)
```

### System Prompt — Stylist Agent

```markdown
You are an expert NYC personal stylist AI. Your job is to recommend the perfect 
outfit from the user's wardrobe for a specific time, place, and occasion in NYC.

## Your Process:
1. PLAN: Decompose the request. What do you need to know?
2. GATHER: Fetch weather, check inventory, optionally check street trends
3. REASON: Consider weather + location microclimate + occasion + user history
4. COMBINE: Build 2-3 complete outfit options from inventory
5. GAP ANALYSIS: If inventory can't fully satisfy the need, suggest purchases
6. PRESENT: Explain your recommendation with reasoning

## Decision Rules:
- ALWAYS check weather for the specific timeframe
- ALWAYS apply location microclimate adjustments:
  - By the Water: wind chill +5-10°F, humidity boost
  - Midtown: urban heat +2-3°F, wind tunnels
  - Downtown: more shade, moderate wind  
  - Uptown: park exposure, true temp
- Check street trends ONLY if: occasion is social, user hasn't specified exact style, 
  or weather is ambiguous (50-65°F zone where choices vary)
- Use user history to break ties between equally suitable options
- ASK the user if the occasion is ambiguous or critical info is missing

## Memory:
- Remember what the user chose, what they rated highly, what they rejected
- Track patterns: "User always picks darker colors for evening"
- Note: "User runs cold" or "User prefers minimal layers"
```

### 2.2 Subagent: Weather Analyst

```python
weather_agent = create_deep_agent(
    model="ollama:mistral-7b-instruct",
    tools=[get_weather, get_historical_weather],
    system_prompt="""You are a weather analyst for NYC. Given a timeframe and location zone,
    fetch the forecast AND apply microclimate adjustments. Return a structured summary:
    - Effective temperature (adjusted for zone)
    - Wind impact
    - Precipitation probability  
    - UV index
    - Layering recommendation (will it change during the timeframe?)
    
    Write your analysis to /session/{id}/weather.json""",
    filesystem_backend=gcs_backend,
)
```

### 2.3 Subagent: Street Scout

```python
street_scout_agent = create_deep_agent(
    model="ollama:mistral-7b-instruct",
    tools=[get_street_trends, describe_clothing_image, compute_similarity],
    system_prompt="""You are a street fashion scout for NYC. Given a location zone and time,
    analyze what people are currently wearing on the street.
    
    Process:
    1. Call get_street_trends(zone, time) to get the latest trend vector + descriptions
    2. Summarize the dominant styles: outerwear types, colors, formality level
    3. Note any weather-adaptive behaviors (umbrellas, hoods up, layers removed)
    4. Write findings to /session/{id}/trends.json
    
    Be concise. Focus on actionable insights for outfit selection.""",
    filesystem_backend=gcs_backend,
)
```

### 2.4 Subagent: Wardrobe Manager

```python
wardrobe_agent = create_deep_agent(
    model="ollama:mistral-7b-instruct",
    tools=[search_inventory, compute_similarity, rate_outfit_coherence, suggest_purchase],
    system_prompt="""You are a wardrobe management expert. Given weather conditions, 
    occasion, and style direction:
    
    1. Search the user's inventory for suitable items per category (top, bottom, outerwear, shoes, accessories)
    2. Score items for weather appropriateness
    3. Build 2-3 complete outfit combinations
    4. Rate each combination for coherence (color harmony, style consistency)
    5. If no suitable item exists for a category, call suggest_purchase
    
    Write candidates to /session/{id}/candidates.json""",
    filesystem_backend=gcs_backend,
)
```

---

## 3. Agent Execution Flow

```
┌────────────────────────────────────────────────────────────────────────────┐
│  USER: "What should I wear tomorrow 6pm, dinner in Midtown, semi-formal"  │
└────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  STYLIST AGENT — PLANNING PHASE                                            │
│                                                                            │
│  write_todos:                                                              │
│  1. [x] Parse request: tomorrow 6pm, Midtown, semi-formal dinner          │
│  2. [ ] Get weather for tomorrow 6pm-11pm Midtown                         │
│  3. [ ] Check street trends (it's a social occasion)                      │
│  4. [ ] Search wardrobe for semi-formal options                           │
│  5. [ ] Build outfit combos                                               │
│  6. [ ] Check user history for evening/dinner preferences                 │
│  7. [ ] Present recommendation with reasoning                             │
└────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
         ┌─────────────────┐ ┌────────────┐ ┌──────────────────┐
         │  WEATHER AGENT  │ │ STREET     │ │ WARDROBE AGENT   │
         │  (subagent)     │ │ SCOUT      │ │ (subagent)       │
         │                 │ │ (subagent) │ │                  │
         │  → Fetches      │ │            │ │ → Searches       │
         │    forecast     │ │ → Checks   │ │   inventory      │
         │  → Applies      │ │   Midtown  │ │ → Filters for    │
         │    Midtown      │ │   cameras  │ │   semi-formal    │
         │    heat island  │ │ → Notes:   │ │ → Pre-scores by  │
         │  → Notes: 62°F  │ │   "blazers │ │   warmth range   │
         │    effective,   │ │   common,  │ │                  │
         │    light wind   │ │   dark     │ │                  │
         │                 │ │   colors"  │ │                  │
         └─────────────────┘ └────────────┘ └──────────────────┘
                    │               │               │
                    └───────────────┼───────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  STYLIST AGENT — SYNTHESIS PHASE                                           │
│                                                                            │
│  Reads: /session/{id}/weather.json                                         │
│  Reads: /session/{id}/trends.json                                          │
│  Reads: /session/{id}/candidates.json                                      │
│  Reads: /memory/{user_id}/history.json                                     │
│                                                                            │
│  Reasoning:                                                                │
│  "62°F in Midtown at 6pm = comfortable but will cool to 55°F by 11pm.     │
│   Semi-formal dinner + street scouts show blazers are common tonight.      │
│   User historically picks navy/charcoal for evening events.                │
│   User rated the navy blazer + gray chinos combo 5/5 last month.           │
│                                                                            │
│   Recommendation: Navy blazer, white oxford shirt, charcoal chinos,        │
│   brown leather oxford shoes. Bring the lightweight scarf for the walk     │
│   back — it'll be 55°F by then."                                           │
│                                                                            │
│  Gap: "You don't have a pocket square — consider one for $15-25 range."    │
└────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  OUTPUT TO USER                                                            │
│                                                                            │
│  Primary Outfit:                                                           │
│  [photo] Navy blazer + [photo] White oxford + [photo] Charcoal chinos     │
│  [photo] Brown oxfords + [photo] Lightweight navy scarf (for later)       │
│                                                                            │
│  Why: "62°F dropping to 55°F, light wind. Blazers are trending on the     │
│  street tonight in Midtown. This combo scored highest in your history      │
│  for similar occasions."                                                   │
│                                                                            │
│  Missing: Navy pocket square — [Shop suggestions]                          │
│                                                                            │
│  [👍 I'll wear this] [🔄 Show alternatives] [💬 Adjust something]          │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. When the Agent is SMARTER Than a Pipeline

### Example: Ambiguous Weather

```
Pipeline: 58°F → applies fixed rule → suggests light jacket

Agent thinks: "58°F at 3pm walking around SoHo = t-shirt weather for most people.
But this user noted they 'run cold' last time. And they're by the water where 
wind chill makes it feel 52°F. Suggesting a light sweater + jacket they can 
remove. Also it's a first date occasion — checking if they have something 
that's stylish AND functional..."
```

### Example: Multi-Stop Day

```
User: "I have a meeting at 9am in Midtown, then lunch Downtown, 
       then a gallery opening by the water at 7pm"

Pipeline: Would need 3 separate runs, can't optimize across them.

Agent plans:
"Three different microclimates and formality levels in one day. 
Need to find an outfit that transitions. Morning = professional (Midtown, 
52°F). Lunch = slightly more relaxed (Downtown, 58°F). Evening = 
creative-formal (waterfront, 48°F with wind).

Strategy: Dark tailored coat bridges all three. Underneath: 
button-down works for meeting + gallery. Swap sneakers for dress shoes 
not practical — recommend versatile leather Chelsea boots. 
The coat handles the temperature swing."
```

### Example: Contradictory Signals

```
Pipeline: Street trend says "everyone in shorts" + Occasion = "business meeting" → conflict, picks one arbitrarily.

Agent reasons: "Street trend shows shorts because it's 80°F. But user has a 
business meeting. Ignore street trend for this occasion — formality overrides. 
However, I'll use the street data to know: lightweight fabrics are key because 
it IS hot. Recommend the lightest-weight dress pants and a breathable shirt."
```

---

## 5. Deep Agents + Open-Weight Integration

### Model Allocation

| Agent Role | Model | Why |
|------------|-------|-----|
| **Stylist (Root)** | Mistral-7B-Instruct + LoRA | Needs strong reasoning, tool use, and style knowledge. LoRA trained on fashion advice. |
| **Weather Analyst** | Mistral-7B (shared instance) | Lightweight task, same model can handle |
| **Street Scout** | Mistral-7B (shared instance) | Summarization task, delegates vision to LLaVA |
| **Wardrobe Manager** | Mistral-7B (shared instance) | Inventory search + combination logic |
| **Vision Tasks** | LLaVA-NeXT-13B | Called as a tool, not an agent. Describes images on demand. |
| **Embeddings/Detection** | CLIP/YOLO/SAM/FashionCLIP | Called as tools via Triton. Not agentic. |

> **Key insight:** The agents all share the SAME vLLM Mistral-7B instance. 
> Different system prompts make them behave as different specialists.
> Only 1 GPU pod needed for the "brain" — LLaVA and Triton handle vision.

### Filesystem Backend: Cloud Storage

```python
from deepagents.backends import GCSFilesystemBackend

gcs_backend = GCSFilesystemBackend(
    bucket="nyc-stylist-agent-workdir",
    prefix="sessions/",
)
```

Each session gets isolated working directory. Persists across requests for multi-turn conversations.

### Memory Backend: Firestore

```python
from langgraph.store import FirestoreStore

memory_store = FirestoreStore(
    collection="agent_memory",
    # Stores: user preferences, past recommendations, learned patterns
)
```

---

## 6. Comparison: Pipeline vs Agentic

| Dimension | Rigid Pipeline (Previous) | Deep Agents (Proposed) |
|-----------|--------------------------|------------------------|
| **Latency (simple request)** | ~2s (all steps run) | ~1-3s (agent may skip steps) |
| **Latency (complex request)** | ~2s (same, can't go deeper) | ~5-10s (deeper reasoning) |
| **Edge case handling** | Fails silently, gives mediocre result | Reasons through ambiguity |
| **Multi-stop days** | Not supported | Natural decomposition |
| **Explainability** | Score numbers | Natural language reasoning |
| **Learning** | Vector updates only | Memory + reasoning adaptation |
| **User interaction** | One-shot in, one-shot out | Conversational, can ask questions |
| **Street trends** | Always computed (wasteful) | Only when relevant to request |
| **Code complexity** | Simpler, more predictable | More complex, more capable |
| **Debugging** | Easy (follow the pipeline) | Harder (need tracing → LangSmith) |

---

## 7. Updated GCP Architecture with Deep Agents

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GCP PROJECT                                          │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Cloud Run (Serverless)                                              │   │
│  │                                                                     │   │
│  │  ┌─────────────┐ ┌──────────────────────────────────────────────┐  │   │
│  │  │ Frontend    │ │  Agent Orchestrator Service (FastAPI)          │  │   │
│  │  │ (Next.js)   │ │  ├── Deep Agent runtime                       │  │   │
│  │  │             │ │  ├── Tool definitions                          │  │   │
│  │  │             │ │  ├── Session management                        │  │   │
│  │  │             │ │  └── Streaming responses (SSE)                 │  │   │
│  │  └─────────────┘ └──────────────────────────────────────────────┘  │   │
│  │                                                                     │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │   │
│  │  │  Weather Tool     │  │  Inventory Tool  │  │  Street Feed    │  │   │
│  │  │  Service          │  │  Service         │  │  Tool Service   │  │   │
│  │  │  (standalone API) │  │  (standalone API)│  │  (standalone)   │  │   │
│  │  └──────────────────┘  └──────────────────┘  └─────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  GKE Autopilot (GPU Inference)                                       │   │
│  │                                                                     │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │  vLLM (Mistral-7B-Instruct + LoRA)                          │   │   │
│  │  │  ← ALL agent reasoning goes through this single endpoint     │   │   │
│  │  │  ← OpenAI-compatible: /v1/chat/completions                   │   │   │
│  │  │  ← Deep Agents connects via langchain-ollama or custom       │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  │                                                                     │   │
│  │  ┌─────────────┐  ┌──────────────────┐  ┌──────────────────────┐  │   │
│  │  │ vLLM        │  │ Triton           │  │ Qdrant               │  │   │
│  │  │ (LLaVA-NeXT)│  │ (YOLO+SAM+CLIP  │  │ (Vector DB)          │  │   │
│  │  │ [vision]    │  │  +FashionCLIP)   │  │                      │  │   │
│  │  └─────────────┘  └──────────────────┘  └──────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌──────────────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐    │
│  │ Cloud SQL (Inv.) │  │Firestore │  │ BigQuery │  │ Cloud Storage  │    │
│  │                  │  │(Memory)  │  │(Analytics│  │ (Images+Models │    │
│  │                  │  │          │  │+Training)│  │  +Agent Files) │    │
│  └──────────────────┘  └──────────┘  └──────────┘  └────────────────┘    │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Cloud Scheduler (Street feed ingestion every 15min)                  │  │
│  │  Cloud Functions (Frame extraction, webhook handlers)                 │  │
│  │  VPC + Cloud Armor + Secret Manager                                   │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Simplification from Agentic Approach

**Before (6 Cloud Run services):** Frontend, Recommendation Engine, Weather, Inventory, Street Feed, History

**After (4 Cloud Run services):** Frontend, **Agent Orchestrator** (replaces Recommendation Engine + History), Weather Tool, Inventory Tool

The agent orchestrator absorbs the recommendation logic, history management, and decision-making into a single intelligent service.

---

## 8. Tool Definitions (What the Agent Can Call)

```python
# === WEATHER TOOLS ===

def get_weather(location_zone: str, start_time: str, end_time: str) -> dict:
    """Fetch weather forecast for a NYC zone and timeframe.
    
    Args:
        location_zone: One of 'midtown', 'downtown', 'uptown', 'waterfront'
        start_time: ISO datetime for start of period
        end_time: ISO datetime for end of period
    
    Returns:
        {
            "raw_temp_f": 62,
            "effective_temp_f": 58,  # After microclimate adjustment
            "wind_mph": 12,
            "wind_direction": "NE",
            "humidity_pct": 65,
            "precip_probability": 0.15,
            "uv_index": 3,
            "conditions": "partly_cloudy",
            "microclimate_notes": "Wind tunnel effect on 6th Ave adds ~5mph gusts"
        }
    """

# === INVENTORY TOOLS ===

def search_inventory(
    user_id: str,
    category: str = None,         # top, bottom, outerwear, shoes, accessories
    warmth_min: int = None,       # 1-10 scale
    warmth_max: int = None,
    formality_min: int = None,    # 1-10 (1=gym, 10=black tie)
    formality_max: int = None,
    waterproof: bool = None,
    colors: list[str] = None,
    text_query: str = None,       # semantic search via embeddings
) -> list[dict]:
    """Search user's clothing inventory with filters.
    
    Returns list of items with: id, name, category, photo_url, 
    warmth_rating, formality, colors, material, description
    """

def rate_outfit_coherence(item_ids: list[str]) -> dict:
    """Score how well a set of items work together.
    
    Returns: { "score": 0.85, "notes": "Color harmony good, 
    formality mismatch between sneakers and blazer" }
    """

# === STREET TREND TOOLS ===

def get_street_trends(zone: str, time: str = "now") -> dict:
    """Get current street fashion trends for a NYC zone.
    
    Returns:
        {
            "dominant_outerwear": "light_jacket",
            "common_colors": ["navy", "black", "earth_tones"],
            "formality_avg": 5.2,
            "weather_adaptations": ["sunglasses common", "no umbrellas"],
            "trend_summary": "Mostly blazers and light layers, 
                             dark color palette, leather shoes prevalent",
            "sample_descriptions": [...],
            "confidence": 0.82
        }
    """

# === MEMORY TOOLS ===

def get_user_history(user_id: str, context: str) -> dict:
    """Retrieve relevant past recommendations and preferences.
    
    Args:
        context: Natural language context to filter relevant history
                 e.g., "evening dinner occasions" or "cold weather choices"
    
    Returns past selections, ratings, and learned preferences relevant to context.
    """

# === SHOPPING TOOLS ===

def suggest_purchase(
    gap_description: str,
    budget_range: str = None,
    style_match: str = None,
) -> list[dict]:
    """Suggest items to buy that would fill a wardrobe gap.
    
    Returns: [{ "name": "...", "price": "$...", "url": "...", "why": "..." }]
    """

# === HUMAN-IN-THE-LOOP ===

def ask_user(question: str, options: list[str] = None) -> str:
    """Ask the user a clarifying question. Use sparingly.
    
    Only ask if:
    - Occasion is ambiguous and affects the outfit significantly
    - Multiple equally good options exist and preference matters
    - Critical information is missing (e.g., indoor vs outdoor)
    """
```

---

## 9. Skills System (Reusable Agent Patterns)

Deep Agents' skills feature lets us codify common patterns:

```yaml
# skills/nyc_microclimate.md
---
name: apply_nyc_microclimate
description: Adjust raw weather data for NYC location zones
---
Given raw weather data and a location zone, apply these adjustments:
- waterfront: wind_chill += 5-10°F, humidity += 10%
- midtown: temp += 2-3°F (heat island), wind gusts in avenues
- downtown: shade_factor = 0.7 (narrow streets)
- uptown: temp stays raw, park exposure increases wind

# skills/outfit_combination.md  
---
name: build_outfit_combination
description: Assemble a complete outfit from individual items
---
A complete outfit MUST include:
1. Base layer (top)
2. Bottom
3. Footwear
4. Optional: outerwear (if temp < 65°F or rain > 20%)
5. Optional: accessories (bag, scarf, hat, umbrella)

Score each combination for:
- Color harmony (max 2 accent colors)
- Formality consistency (all items within 2 points)
- Weather coverage (all exposed areas addressed)
```

---

## 10. Observability & Tracing

Since agentic systems are harder to debug, we add:

```
┌────────────────────────────────────────────────────────┐
│  OBSERVABILITY STACK                                    │
│                                                        │
│  ┌────────────────────────────────────────────────┐   │
│  │  Langfuse Cloud (SaaS) — chosen backend         │   │
│  │  • Traces every agent step                      │   │
│  │  • Shows tool calls + reasoning                 │   │
│  │  • Latency per step                             │   │
│  │  • Token usage per agent                        │   │
│  │  • Success/failure rates                        │   │
│  └────────────────────────────────────────────────┘   │
│                                                        │
│  ┌────────────────────────────────────────────────┐   │
│  │  Self-host fallback (deferred)                  │   │
│  │  • If data residency demands it later, run      │   │
│  │    Langfuse on GKE + Cloud SQL Postgres         │   │
│  │  • Out of scope for Phase 0–2                   │   │
│  └────────────────────────────────────────────────┘   │
│                                                        │
│  ┌────────────────────────────────────────────────┐   │
│  │  Cloud Monitoring + Prometheus                   │   │
│  │  • GPU utilization                              │   │
│  │  • vLLM queue depth                             │   │
│  │  • Request latency P50/P95/P99                  │   │
│  │  • Agent loop count (detect runaway agents)     │   │
│  └────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────┘
```

---

## 11. Safety Guardrails

| Risk | Mitigation |
|------|-----------|
| Agent loops forever | Max 15 tool calls per request, 30s timeout per subagent |
| Agent hallucinates items | Tools return only REAL inventory items; agent can't invent |
| Agent gives dangerous advice | No health/safety advice in scope; clothing only |
| Cost runaway | Token budget per request (4K input, 2K output per agent call) |
| Privacy leak between users | Session isolation via filesystem permissions |
| Agent asks too many questions | Limit `ask_user` to max 1 per request |

---

## 12. Updated Tech Stack

| Layer | Technology |
|-------|-----------|
| **Agent Framework** | LangChain Deep Agents (`deepagents` package) |
| **Agent Orchestration** | LangGraph (state machine for multi-agent flows) |
| **Agent Memory** | Firestore (via LangGraph Store) |
| **Agent Filesystem** | Cloud Storage backend (GCS) |
| **Agent Tracing** | Langfuse Cloud (SaaS) — `cloud.langfuse.com`; self-host on GKE only if data residency requires it |
| **LLM (Agent Brain)** | Mistral-7B-Instruct + LoRA (via vLLM) |
| **Vision LLM** | LLaVA-NeXT-13B (via vLLM, called as tool) |
| **Detection/Embedding** | YOLOv8 + SAM-2 + CLIP + FashionCLIP (Triton) |
| **Vector DB** | Qdrant |
| **Frontend** | Next.js 14, React, TailwindCSS, shadcn/ui |
| **Backend** | Python (FastAPI) + Deep Agents runtime |
| **Infra** | GKE Autopilot (GPU) + Cloud Run (serverless) |
| **IaC** | Terraform |

---

## 13. Phased Delivery (Revised for Agentic)

### Phase 1 — Agent MVP
1. Single Stylist Agent with basic tools (weather + inventory search)
2. Mistral-7B on vLLM as the agent brain
3. Basic inventory CRUD + CLIP auto-tagging
4. Rule-based weather tool (no street feed yet)
5. Next.js UI with chat-style interaction + outfit display
6. Firestore memory for user preferences
7. GCS filesystem backend for session working memory

### Phase 2 — Multi-Agent + Street Intelligence
8. Subagent spawning (Weather Agent, Street Scout, Wardrobe Manager)
9. Street feed pipeline (YOLO + SAM + LLaVA + FashionCLIP → trend tool)
10. LoRA fine-tuning pipeline for agent reasoning
11. Shopping suggestion tool
12. Langfuse Cloud tracing integration (SaaS)

### Phase 3 — Personalization & Polish
13. Advanced memory (pattern detection across sessions)
14. Skills system (reusable agent patterns)
15. Conversational follow-ups ("actually make it more casual")
16. Multi-stop day planning
17. User feedback → automatic LoRA refresh

---

## 14. Final Verdict: Pipeline vs Deep Agents

**Use Deep Agents because this system is fundamentally about JUDGMENT, not computation.**

A rigid pipeline can fetch weather and filter inventory. But deciding what to wear requires:
- Contextual reasoning (rooftop vs restaurant, time of day, transitions)
- Weighing contradictory signals (hot day but formal event)
- Personalizing to individual quirks ("runs cold", "prefers minimal accessories")
- Explaining choices in a way that builds user trust
- Adapting strategy based on what information is available

These are exactly the problems LLM agents solve well. The open-weight models (Mistral-7B) are strong enough for tool-use and reasoning, and the Deep Agents framework provides the scaffolding (planning, memory, subagents, filesystem) without reinventing it.

**The key architectural insight:** Models like YOLO, SAM, CLIP, and FashionCLIP remain as **tools** (not agents). They don't reason — they compute. The agents DECIDE when and how to use them.
