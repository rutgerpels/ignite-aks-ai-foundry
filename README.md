# Hands-on lab: Deploy and run Microsoft Foundry models and agents on AKS

A reproducible lab based on the Microsoft Ignite session **"Deploy and run Microsoft Foundry models and agents on AKS"** (Brendan Burns & Jorge Palma). It follows the session's story: **Caldova Pharmaceuticals**, a regulated manufacturer with 4 plants and 120 lines, wants an AI agent that cuts the time to troubleshoot production-line micro-stops. It has to run on the AKS infrastructure Caldova already has approved, under Caldova's control, across cloud and plant sites.

> `azd up` deploys the **infrastructure and a working CPU-based agent**. The new **preview features** (AKS AI Manager, Foundry AKS compute, Flex nodes, Agent Sandbox, Agent Grid) are configured **by you**, step by step, in the modules below. That's the point of the lab.

## Architecture

```
                         ┌──────────────── Microsoft Foundry (account + project) ───────────────┐
                         │  model catalog · AKS compute (module 03) · tracing (App Insights)    │
                         └─────────────▲────────────────────────────────▲─────────────────────────┘
                                       │ AI Manager (module 02)         │ hosted agents
 vnet-cloud 10.10.0.0/16               │                                │
 ┌─────────────────────────────┐   ┌───┴─────────────────────────┐   ┌──┴──────────────────────────┐
 │ aks-inference               │   │ aks-agents (Cilium)          │   │ aks-plant (no CNI → Unbounded)│
 │  • cpumodels pool: Ollama   │◄──┤  • kata pool: caldova-agent  │   │  • flex pool "plant2edge"     │
 │    (internal LB :11434)     │   │  • MCP: plant-signals,       │   │    (module 04)                │
 │  • AI Manager target        │   │         maintenance          │   └──────────────▲───────────────┘
 └─────────────────────────────┘   │  • NetworkPolicy / Agent Grid│                  │ peering
                                   └──────────────────────────────┘   vnet-plant2 10.20.0.0/16
                                                                      vm-plant2-edge (flex node host)
 ACR · Log Analytics · Application Insights
```

## Session → lab map

| Session (approx.) | Topic | Module |
|---|---|---|
| 00:00–06:30 | Agents rewrite infrastructure; AKS as the AI foundation | – |
| 06:30–09:00 | AKS AI Manager: deploy open-weight Foundry models to AKS with one API | [02](docs/02-aks-ai-manager.md) |
| 09:00–12:30 | Caldova scenario, production-line app | `azd up` → agent UI |
| 12:30–15:00 | Foundry resource with **AKS compute** for agent hosting | [03](docs/03-foundry-aks-compute.md) |
| 15:00–19:00 | Heterogeneous, on-prem, multi-plant: **Flex nodes** | [04](docs/04-flex-nodes.md) |
| 20:00–24:00 | Sandboxing: **Kata** / **Agent Sandbox** | [05](docs/05-pod-sandboxing-agent-sandbox.md) |
| 24:00–30:00 | Policy and governed egress: **Agent Grid** | [06](docs/06-agent-grid.md) |
| 30:00+ | Observable, auditable, cost | [07](docs/07-observability-cost.md) |

## Quick start

```powershell
# see docs/01-prerequisites.md for tools, feature flags and preview sign-ups
azd auth login            # or: azd config set auth.useAzCliAuth true
azd env new ignite-aks
azd env set AZURE_LOCATION swedencentral
azd up                    # ~25 min: infra + images + Ollama + agent (postprovision hook)
azd env get-value AGENT_URL
```

Open `AGENT_URL`, pick **line-7** and run **Guided** or **Autonomous** troubleshooting. The agent:
1. reads live signals and alarms via the **plant-signals** MCP server,
2. searches the equipment manual and maintenance history via the **maintenance** MCP server,
3. proposes a root cause, a restart procedure and a work order draft.

**Guided** runs a fixed tool plan; **Autonomous** lets the model choose the MCP tools via function calling. **Inspect** sends a camera frame to a vision model.

Models: `qwen2.5:1.5b` (chat) and `moondream` (vision) on CPU with Ollama, so it works without GPU quota. Expect about 30 s per guided run. The 1.5B model is weak at multi-step tool calling in **Autonomous** mode (it often stops after one tool). That's a good set-up for module 02, where AI Manager serves a larger model on GPU. Module 02 swaps it for an AI Manager GPU deployment with a single configmap change.

## Repo layout

| Path | Content |
|---|---|
| `infra/` | Bicep (azd): network, 3× AKS, edge VM, Foundry, ACR, monitoring, roles |
| `src/agent` | FastAPI agent + UI (OpenAI-compatible client, MCP client, OpenTelemetry) |
| `src/mcp-*` | Mock MCP servers (Streamable HTTP) with Caldova line data and manuals |
| `k8s/` | Ollama, agent (Kata runtime), MCP servers, network policy |
| `scripts/` | `deploy-apps.ps1` (postprovision), `new-flex-env.ps1` (module 04) |
| `docs/` | Lab modules 01–08 |

## Disclaimer

Several features are **preview / limited preview** and change often. Commands follow the docs as of the session. If a command fails, check the linked Learn article. Caldova is fictional. Clean up with [module 08](docs/08-cleanup.md).
