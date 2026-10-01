<div align="center">

# ✈️ TripMate AI

**A LangGraph multi-agent travel planner with a Supervisor, Guardrails, Human-in-the-Loop review, and real tool access through the Model Context Protocol (MCP).**

[![Python](https://img.shields.io/badge/Python-3.13-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.136-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![LangGraph](https://img.shields.io/badge/LangGraph-1.2-1C3C3C?logo=langchain&logoColor=white)](https://langchain-ai.github.io/langgraph/)
[![MCP](https://img.shields.io/badge/MCP-1.28-6E56CF)](https://modelcontextprotocol.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

## 📖 Table of Contents

- [Overview](#-overview)
- [Screenshots](#-screenshots)
- [Key Features](#-key-features)
- [System Architecture](#-system-architecture)
- [Multi-Agent Workflow](#-multi-agent-workflow)
- [Human-in-the-Loop Flow](#-human-in-the-loop-flow)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Environment Variables](#-environment-variables)
- [Installation](#-installation)
- [Running the App](#-running-the-app)
- [API Reference](#-api-reference)
- [How It Works](#-how-it-works)
- [Troubleshooting](#-troubleshooting)
- [License](#-license)
- [Author](#-author)

---

## 🧭 Overview

**TripMate AI** turns a single natural-language request (for example, *"Plan a 7-day Japan trip from Bangladesh under 2 lakhs"*) into a polished, ready-to-use travel plan.

Instead of one monolithic prompt, a **supervisor agent** decides which specialist agents are needed, each specialist pulls **live data through MCP servers**, a **guardrail** keeps the app on-topic, and a **human reviews the draft itinerary** before the final plan is generated. Every run is checkpointed to **PostgreSQL**, so an interrupted plan can be resumed exactly where it paused.

> **Why it's interesting:** it demonstrates a realistic production pattern — *routing + tool use + guardrails + human approval + durable state* — rather than a single LLM call.

---

## 🖼️ Screenshots

### Landing page

![TripMate AI landing page — hero section and travel request planner](docs/screenshot-home.png)

### Generated draft awaiting human review

After a request is submitted, the supervisor's plan (agent chips + guardrail status) and the draft itinerary are shown, and the graph pauses for the human-in-the-loop approval.

![TripMate AI draft itinerary with supervisor execution plan and human-in-the-loop approval buttons](docs/screenshot-plan.png)

---

## ✨ Key Features

| Feature | Description |
| --- | --- |
| 🧠 **Supervisor Agent** | Reads the request and selects only the specialist agents that are needed (plus the itinerary agent, always). |
| 🛡️ **Input Guardrail** | Blocks non-travel or harmful requests and fails *open* on parser errors so valid trips are never lost to a format glitch. |
| ✈️🏨🌦️💰🗓️ **Specialist Agents** | Flight, Hotel, Weather, Budget and Itinerary agents, each with its own prompt and data source. |
| 🔌 **MCP Tool Access** | Live tools via `langchain-mcp-adapters`: Tavily (HTTP), AviationStack (uvx stdio) and a local Weather server (Python stdio). |
| 👤 **Human-in-the-Loop** | The graph **pauses** on an `interrupt()`, shows the draft, and resumes with an approval or revision feedback. |
| 💾 **Durable State** | LangGraph `PostgresSaver` checkpoints every step, enabling resume-by-`thread_id`. |
| 🖥️ **FastAPI + Web UI** | A clean single-page frontend with Markdown rendering, copy and **Download PDF** support. |
| 🧩 **Graceful Degradation** | If a tool or API key is unavailable, the relevant agent falls back to labeled general guidance instead of crashing. |
| 🐳 **One-command run** | `./run.sh` frees the port and starts the server (no stale-server surprises). |

---

## 🏗️ System Architecture

![TripMate AI system architecture](docs/architecture.svg)

The system is layered so each concern is isolated:

1. **Client** — a static single-page UI (`template/index.html`, `static/`) served by FastAPI.
2. **API** — `app.py` exposes the endpoints, validates payloads with Pydantic, and returns JSON.
3. **Orchestration** — `backend.py` defines the LangGraph `StateGraph`: supervisor → specialists → human approval → final response, backed by a PostgreSQL checkpointer.
4. **MCP Layer** — `mcp_client.py` builds a `MultiServerMCPClient` and loads **only the tool it needs per call**, so one broken server can't take down an unrelated request.
5. **External Services** — Groq (LLM), Tavily (search), AviationStack (flights), OpenWeather (weather) and PostgreSQL (state).

---

## 🔀 Multi-Agent Workflow

```mermaid
flowchart TD
    START([START]) --> SUP["🧠 Supervisor Agent<br/>+ Input Guardrail"]
    SUP -->|"blocked"| BLOCK["🛡️ Guardrail Blocked Response"]
    BLOCK --> END1([END])
    SUP -->|"allowed"| ROUTE{"Route to first<br/>selected agent"}

    ROUTE --> F["✈️ Flight Agent"]
    F --> H["🏨 Hotel Agent"]
    H --> W["🌦️ Weather Agent"]
    W --> B["💰 Budget Agent"]
    B --> I["🗓️ Itinerary Agent"]

    ROUTE -.->|"skips unselected"| H
    ROUTE -.->|"skips unselected"| W
    ROUTE -.->|"skips unselected"| B

    I --> HA{{"👤 Human Approval<br/>(interrupt)"}}
    HA -->|"approved / feedback"| FIN["🏁 Final Response Agent"]
    FIN --> END2([END])

    style SUP fill:#f5f3ff,stroke:#a78bfa
    style HA fill:#fef2f2,stroke:#fca5a5
    style FIN fill:#ecfdf5,stroke:#6ee7b7
```

**Routing rules**

- The supervisor always appends `itinerary_agent`, so there is always an integrated draft.
- `route_after_agent()` walks the fixed `AGENT_ORDER` — `flight → hotel → weather → budget → itinerary` — and **skips any agent the supervisor did not select**.
- If the guardrail blocks the request, the graph short-circuits to a blocked response and ends.
- After the itinerary is built, control always passes through **Human Approval** and then the **Final Response Agent**.

---

## 👤 Human-in-the-Loop Flow

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant UI as Browser UI
    participant API as FastAPI (app.py)
    participant Graph as LangGraph (backend.py)
    participant MCP as MCP Servers
    participant DB as PostgreSQL

    User->>UI: Enter a travel request
    UI->>API: POST /api/travel
    API->>Graph: invoke(user_input, thread_id)
    Graph->>Graph: Supervisor + Guardrail
    Graph->>MCP: Call specialist tools
    MCP-->>Graph: Flights / Hotels / Weather
    Graph->>DB: Checkpoint state
    Graph-->>API: __interrupt__ (draft itinerary)
    API-->>UI: requires_approval = true + draft
    UI-->>User: Show draft + Approve / Revise

    alt Approved
        User->>UI: Approve & Generate Final
    else Revision requested
        User->>UI: Provide feedback
    end

    UI->>API: POST /api/travel/approve
    API->>Graph: resume(Command(resume=...))
    Graph->>DB: Load checkpoint by thread_id
    Graph->>Graph: Final Response Agent
    Graph->>DB: Checkpoint final state
    Graph-->>API: final_response
    API-->>UI: Final plan
    UI-->>User: Render (copy / Download PDF)
```

---

## 🧰 Tech Stack

| Layer | Technology |
| --- | --- |
| **Web framework** | FastAPI · Uvicorn · Jinja2 |
| **Orchestration** | LangGraph `StateGraph` · `interrupt()` / `Command(resume=…)` |
| **LLM** | Groq (`openai/gpt-oss-120b`) via `langchain-groq` |
| **Tools / Protocols** | Model Context Protocol (MCP) via `langchain-mcp-adapters` |
| **MCP servers** | Tavily (`streamable_http`) · AviationStack (`uvx` stdio) · Local Weather server (`stdio`) |
| **Persistence** | PostgreSQL via `langgraph-checkpoint-postgres` (`PostgresSaver`) |
| **Frontend** | Vanilla JS · `marked.js` (Markdown) · `html2pdf.js` (PDF export) |
| **Config** | `python-dotenv` |
| **Observability (optional)** | LangSmith |

---

## 📁 Project Structure

```text
MultiAgent-using-MCP/
├── app.py                        # FastAPI app: routes, Pydantic models, static & templates
├── backend.py                    # LangGraph: supervisor, guardrail, agents, HITL, checkpointer
├── mcp_client.py                 # MCP client + tool wrappers + destination extractor
├── custom_weather_mcp_server.py  # Local MCP server (OpenWeather) over stdio
├── main.py                       # Placeholder entry point
├── run.sh                        # Port-safe launcher (kills stale server, then starts uvicorn)
├── template/
│   └── index.html                # Single-page UI (note: singular "template/")
├── static/
│   ├── style.css                 # UI styling
│   └── script.js                 # Fetch calls, Markdown render, PDF export
├── docs/
│   └── architecture.svg          # Architecture diagram used in this README
├── pyproject.toml                # Project metadata + dependencies (uv)
├── requirements.txt              # Pip-style dependency pins
├── uv.lock                       # Locked dependency graph
├── .python-version               # 3.13
├── .env                          # Secrets (git-ignored — create your own)
└── LICENSE                       # MIT
```

> **Note:** the UI folder is `template/` (singular) and `app.py` points Jinja2 at it. If you move it, update `Jinja2Templates(directory=...)` in `app.py`.

---

## ✅ Prerequisites

- **Python 3.13+**
- **[uv](https://docs.astral.sh/uv/)** — required because the AviationStack MCP server is launched with `uvx`
- A **Groq API key** (LLM)
- A **PostgreSQL** database URL (state checkpoints)
- A **Tavily API key** (search)
- An **AviationStack API key** (flights)
- *(Optional)* an **OpenWeather API key** (live weather)

---

## 🔐 Environment Variables

Create a `.env` file in the project root. Only `GROQ_API_KEY` and `DATABASE_URL` are hard requirements — the rest degrade gracefully when absent.

| Variable | Required | Used by | Purpose |
| --- | :---: | --- | --- |
| `GROQ_API_KEY` | ✅ | `backend.py`, `mcp_client.py` | Access to the Groq LLM. |
| `DATABASE_URL` | ✅ | `backend.py` | PostgreSQL URL for LangGraph checkpoints. `sslmode=require` is appended automatically if missing. |
| `TAVILY_API_KEY` | ➖ | `mcp_client.py` | Web search for hotels, sights and tips. |
| `AVIATIONSTACK_API_KEY` / `AVIATION_STACK_API_KEY` | ➖ | `mcp_client.py` | Airport/airline data. Both spellings are accepted. |
| `OPENWEATHER_API_KEY` | ➖ | `custom_weather_mcp_server.py` | Live current weather + forecast. |
| `DEFAULT_ORIGIN_IATA` | ➖ | Available to agents | Default departure airport code. |
| `LANGSMITH_TRACING`, `LANGSMITH_ENDPOINT`, `LANGSMITH_API_KEY`, `LANGSMITH_PROJECT` | ➖ | LangSmith | Optional tracing/observability. |

Example `.env`:

```dotenv
GROQ_API_KEY=your_groq_key
DATABASE_URL=postgresql://user:pass@host:5432/dbname?sslmode=require
TAVILY_API_KEY=your_tavily_key
AVIATIONSTACK_API_KEY=your_aviationstack_key
OPENWEATHER_API_KEY=your_openweather_key
DEFAULT_ORIGIN_IATA=DAC
```

> ⚠️ `.env` is git-ignored. Never commit real keys.

---

## 📦 Installation

```bash
# 1. Clone
git clone https://github.com/Yogeshwaran197/MultiAgent-using-MCP.git
cd MultiAgent-using-MCP

# 2. Create the virtual environment (Python 3.13)
uv venv            # or: python -m venv .venv

# 3. Install dependencies
uv sync            # or: pip install -r requirements.txt

# 4. Add your credentials
cp .env.example .env   # then edit .env  (see the table above)
```

Make sure `uv`/`uvx` is on your `PATH` — the AviationStack MCP server is started with `uvx aviationstack-mcp`.

---

## ▶️ Running the App

The recommended way — it **frees the target port first**, so a stale server can never keep serving old code:

```bash
./run.sh              # http://127.0.0.1:8000
PORT=8080 ./run.sh    # custom port
./run.sh --reload     # extra flags are passed through to uvicorn
```

Then open **http://127.0.0.1:8000**.

<details>
<summary>Manual start (and how to restart safely on Windows)</summary>

```bash
# Manual start
.venv/Scripts/python.exe -m uvicorn app:app --host 127.0.0.1 --port 8000   # Windows
.venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port 8000           # macOS / Linux
```

On Windows, `pkill` does **not** terminate native processes. Find and kill the listener directly:

```bash
netstat -ano | grep :8000            # note the PID
taskkill //F //PID <pid>             # force-kill it
```
</details>

---

## 🔌 API Reference

### `POST /api/travel`

Start a new planning run. The graph executes the supervisor, the selected specialists and the itinerary agent, then **pauses for human review**.

**Request**

```json
{
  "message": "Plan a 7-day Japan trip from Bangladesh under 2 lakhs",
  "thread_id": null
}
```

> `thread_id` is optional. When omitted, the server generates `user_<uuid>` and returns it — pass it back to continue the same conversation thread.

**Response (draft ready for review)**

```json
{
  "success": true,
  "thread_id": "user_1a2b3c4d…",
  "requires_approval": true,
  "answer": "…draft itinerary markdown…",
  "itinerary": "…draft itinerary markdown…",
  "approval_request": "Please review the generated draft itinerary…",
  "selected_agents": ["flight_agent", "hotel_agent", "weather_agent", "budget_agent", "itinerary_agent"],
  "trip_constraints": { "destination": "Japan", "origin": "Bangladesh", "budget": "2 lakh", "…": "…" },
  "supervisor_reasoning": "…",
  "guardrail_allowed": true,
  "flight_results": "…", "hotel_results": "…", "weather_results": "…", "budget_results": "…",
  "llm_calls": 6
}
```

### `POST /api/travel/approve`

Resume a paused thread with an approval or revision feedback.

**Request**

```json
{
  "thread_id": "user_1a2b3c4d…",
  "approved": true,
  "feedback": ""
}
```

- `approved: true` → the final agent polishes the draft.
- `approved: false` → `feedback` is **required** and drives the revision.

**Response** — same shape as above, with `final_response` populated and `requires_approval: false`.

### `GET /` · `GET /health`

| Route | Returns |
| --- | --- |
| `GET /` | The Jinja2-rendered UI (`index.html`). |
| `GET /health` | `{ "status": "ok", "message": "TripMate AI API is running", "features": [...] }`. |
| `GET /favicon.ico` | Empty JSON (avoids 404 noise). |

**Try it**

```bash
curl -X POST http://127.0.0.1:8000/api/travel \
  -H "Content-Type: application/json" \
  -d '{"message":"3 day trip to Paris from London"}'
```

---

## ⚙️ How It Works

<details>
<summary><strong>Supervisor &amp; Guardrail</strong></summary>

The first node runs two LLM steps against strict JSON:
1. **Guardrail** — returns `{ "allowed": bool, "reason": str }`. Off-topic or harmful requests are blocked; valid trips with missing details are *not* blocked. On any parse/model error it **fails open**.
2. **Supervisor** — returns `selected_agents`, `trip_constraints` and `reasoning`. Unknown agent names are ignored and `itinerary_agent` is force-included. On a parse failure it falls back to running the full original workflow.

</details>

<details>
<summary><strong>Agents</strong></summary>

| Agent | Data source | Fallback |
| --- | --- | --- |
| ✈️ Flight | AviationStack MCP (`list_airports`, `list_airlines`) | General route/airline knowledge when data is unavailable. |
| 🏨 Hotel | Tavily MCP search | Labeled non-live accommodation advice. |
| 🌦️ Weather | Local Weather MCP (`get_current_weather`, `get_forecast`) | General seasonal guidance + "verify before departure". |
| 💰 Budget | Groq LLM over collected results | Estimates clearly labeled as approximate. |
| 🗓️ Itinerary | Groq LLM over all selected results | Produces the draft that awaits review. |

Each MCP call loads **only its own server's tools**, so a failing Tavily/AviationStack/Weather server cannot crash an unrelated request.

</details>

<details>
<summary><strong>Checkpointing &amp; resume</strong></summary>

`backend.py` opens a `psycopg` connection to `DATABASE_URL` and compiles the graph with `PostgresSaver`.
- `run_travel_agent()` calls `travel_graph.invoke(state, config={"configurable": {"thread_id": id}})` and stops at the `interrupt()`.
- `resume_travel_agent()` calls `travel_graph.invoke(Command(resume={...}), config=…)` to continue the same thread.

Because state lives in PostgreSQL, the approval step can happen seconds or days later.

</details>

---

## 🛠️ Troubleshooting

<details open>
<summary><strong>404 — model does not exist / no access</strong></summary>

```
The model `llama-3.3-70b-versatile` does not exist or you do not have access to it.
```

Groq retired that model. Both `backend.py` and `mcp_client.py` use `openai/gpt-oss-120b`, which your key must have access to. Confirm the exact model string in **both** files, then restart the server. To list the models your key can use:

```bash
python -c "import os,requests; from dotenv import load_dotenv; load_dotenv(); \
print('\n'.join(m['id'] for m in requests.get('https://api.groq.com/openai/v1/models', \
headers={'Authorization':f\"Bearer {os.environ['GROQ_API_KEY']}\"}).json()['data']))"
```
</details>

<details>
<summary><strong>My code change has no effect</strong></summary>

You are almost certainly hitting a **stale server**. On Windows, `pkill` doesn't terminate native processes, so an old server keeps the port. Use `./run.sh` (which frees the port) or kill it explicitly:

```bash
netstat -ano | grep :8000
taskkill //F //PID <pid>
```
</details>

<details>
<summary><strong>AviationStack: <code>function_access_restricted</code></strong></summary>

Your AviationStack plan doesn't include `list_airports` / `list_airlines`. The flight agent degrades to the LLM's general knowledge; upgrade the plan to restore live airport/airline data.
</details>

<details>
<summary><strong>Weather says "live information unavailable"</strong></summary>

`OPENWEATHER_API_KEY` is missing or invalid. Add it to `.env`; until then the weather agent returns labeled seasonal guidance.
</details>

<details>
<summary><strong><code>python-dotenv could not parse statement at line N</code></strong></summary>

A line in `.env` is malformed (for example an accidental free-text line). Remove or fix it — it's a warning, not a fatal error.
</details>

<details>
<summary><strong>`DATABASE_URL is missing` / `GROQ_API_KEY is missing`</strong></summary>

These two are required at import time. Create `.env` in the **project root** (next to `app.py`) and set both.
</details>

---

## 📄 License

Released under the **MIT License** — see [LICENSE](LICENSE).

---

## 👤 Author

**Yogeshwaran D** — [@Yogeshwaran197](https://github.com/Yogeshwaran197)

Built with **FastAPI · LangGraph · Groq · PostgreSQL · Tavily · AviationStack · MCP**.

<div align="center">
<sub>If this project helped you, consider giving it a ⭐.</sub>
</div>
