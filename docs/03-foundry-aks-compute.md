# 03 – Foundry with AKS compute (models and hosted agents on your cluster)

**Session ref:** 12:20–14:30 (create Foundry resource → connected resources → agent hosting: *AKS compute*), and the later "deploy the agent to AKS" walkthrough.

The lab already created the Foundry account `aif-caldova-*` and project `caldova-line-troubleshooting`, with App Insights connected. In this module you connect your **own AKS clusters** so Foundry can place model deployments and hosted agents there.

> Requires limited-preview approval: https://aka.ms/byoaks-foundry-registration. Without it, the AKS options below are not visible; read on and show the CLI/K8s equivalent instead.

## 1. Inspect what's deployed

```powershell
azd env get-values | Select-String 'FOUNDRY|AKS_'
```

Open https://ai.azure.com, select the project **caldova-line-troubleshooting**.

## 2. Attach the inference cluster as compute

1. **Management center → Compute clusters → Add cluster**.
2. Choose the subscription and **aks-inference-\***.
3. Foundry installs/uses AI Manager on the cluster (module 02). If you already created `aim-caldova`, it is reused.
4. In **Model catalog**, pick an open-weight model → **Deploy → AKS compute** → select the cluster and a VM size (GPU required).

Talking point: same catalog, same governance (Content Safety, RBAC, tracing) as a serverless deployment, but the weights run on infrastructure you already certified.

## 3. Attach the agent cluster for agent hosting

1. **Management center → Connected resources / Agent hosting → AKS compute → Add**.
2. Select **aks-agents-\***. Foundry deploys hosted agents as pods on this cluster.
3. Use an identity: the project managed identity, or bring your own user-assigned identity with access to the cluster.

Recommended: target the Kata pool so each hosted agent runs in its own micro-VM (module 05).

## 4. Deploy a hosted agent

Hosted agents are container images that implement the Foundry agent protocol. Two routes:

**A. Portal** – *Agents → New hosted agent →* image from `acr*.azurecr.io`, hosting target *AKS compute*.

**B. azd (`azure.ai.agents` extension)**

```powershell
azd extension install azure.ai.agents
azd ai agent init        # scaffold; choose "hosted", point at this project
azd ai agent deploy      # choose AKS compute as the host when prompted
```

The sample agent in `src/agent` is a plain FastAPI + MCP app that already runs on `aks-agents` (deployed by `azd up`). It is the "bring your own agent" version of the same idea; use it as the fallback demo if the preview isn't enabled.

## 5. Foundry observability

`deploy-apps.ps1` sets `APPLICATIONINSIGHTS_CONNECTION_STRING` (the App Insights connected to the project) on the agent. The agent then exports OpenTelemetry traces, including `gen_ai` spans for every model call and the HTTP spans for MCP tool calls. Run a troubleshoot from the UI, then open **Foundry → Tracing** (or App Insights → Transaction search) to show the end-to-end trace.
