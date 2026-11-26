# Code experience

[Lab home](../../README.md) | [Start module 01](01-prerequisites.md)

Follow this folder from setup to cleanup. Run PowerShell commands in **PowerShell 7 from the repository root**, not from this documentation folder. Module 04 explicitly switches to Linux-compatible Bash and then the edge host. Relative paths such as `.kube/agents` always start at the repository root.

The original Bicep, scripts, manifests and application workflow remain the code track. Any required portal operations are explained in the relevant module; no portal-track module is a prerequisite.

## Modules

| Order | Module | What you accomplish |
|---|---|---|
| 01 | [Access, setup and CPU baseline](01-prerequisites.md) | Check permissions/quota, deploy once, verify Guided and record a baseline. |
| 02 | [AI Manager](02-aks-ai-manager.md) | Optionally deploy one feasible GPU model, test it, switch chat safely and retain rollback. |
| 03 | [Foundry project and hosting boundary](03-foundry-aks-compute.md) | Inspect the project; distinguish the AKS app from access-gated hosted-agent onboarding. |
| 04 | [Flex nodes](04-flex-nodes.md) | Prepare plant networking, bootstrap the edge host and verify workload placement. |
| 05 | [Kata and Agent Sandbox](05-pod-sandboxing-agent-sandbox.md) | Verify baseline isolation; attempt Sandbox only with genuine Kata v2 capacity. |
| 06 | [Agent Grid](06-agent-grid.md) | Check eligibility, configure policies and collect attributable allowed/denied evidence. |
| 07 | [Observability and cost](07-observability-cost.md) | Compare actual telemetry and browser outcomes; account for all resources. |
| 08 | [Cleanup](08-cleanup.md) | Remove optional dependencies and confirm resource deletion. |

## Keep the learning flow

Module 01 is the prerequisite for the lab. Modules 02-06 are optional extensions, not cumulative requirements: a skipped GPU, hosting or Flex exercise must not block later baseline inspections. Use each module's **Before**, **Expected/checkpoint**, **Troubleshooting** and **Carry forward** guidance.

Use the existing azd environment if already deployed; do not create a second baseline just because you changed documentation tracks. A separate Malaysia West GPU tier, if selected in module 02, is an explicit exception: keep it in its own resource group and record it for cleanup. Do not change the base environment's region to relocate its resources.

GPU quota is not a guarantee of allocation. There is no verified documented AI Manager Spot selection in this lab; do not budget a deployment as Spot without confirmation. Preview registration is not runtime capability or limited-preview approval. Keep network governance intact.

The baseline agent is a plain FastAPI app with legacy Kata isolation and CPU Ollama models. It is not automatically a Foundry hosted agent, a per-request Sandbox consumer or an Agent Grid member. Each module requires evidence before claiming its optional feature is working.
