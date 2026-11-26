# 03 - Foundry project and the own-AKS hosting boundary

**Session ref:** 12:20-14:30, Foundry with AKS compute and hosted agents.

[Previous: model layer](02-aks-ai-manager.md) | [Code experience](README.md) | [Next: plant compute](04-flex-nodes.md)

**Learn:** distinguish a Foundry project, an inference endpoint, an independently deployed AKS app and a Foundry hosted agent. Module 02 changes the app's model endpoint; it does not register the app with Foundry.

**Before:** complete module 01's working CPU baseline. Module 02's GPU deployment is optional. This module's inspection is read-only; own-AKS hosting requires separate preview access and current onboarding instructions.

## 1. Find the existing project

From PowerShell at the repo root, retrieve only the nonsecret names:

```powershell
azd env get-value FOUNDRY_ACCOUNT_NAME
azd env get-value FOUNDRY_PROJECT_NAME
azd env get-value AKS_AGENTS_NAME
```

In Azure portal, locate `aif-caldova-*`. In [Foundry portal](https://ai.azure.com), select that account's **caldova-line-troubleshooting** project in the same tenant/subscription. If not visible, check project access, directory and subscription before creating anything.

## 2. Compare the resource boundary with the code

1. Read `infra/modules/foundry.bicep`: it creates the account, project with managed identity, and an App Insights connection shared with projects.
2. Read `scripts/deploy-apps.ps1`: it directly applies `k8s/agent/agent.yaml` on `aks-agents-*`.
3. Inspect the running Deployment:

   ```powershell
   kubectl --kubeconfig .kube/agents -n caldova get deployment caldova-agent -o yaml
   kubectl --kubeconfig .kube/agents -n caldova get pods -l app=caldova-agent -o wide
   ```

4. Compare the browser `/api/config` output with module 02's chosen endpoint. Ollama or AI Manager serves inference; neither implies Foundry manages the agent lifecycle.

**Expected:** one plain FastAPI/MCP app runs on the agents cluster. Its App Insights connection is not a Foundry agent registration, hosting connection or automatic Content Safety/tracing guarantee.

## 3. Own-AKS preview: access-gated hand-off

The session demonstrated a preview own-AKS hosting experience. The historical [registration link](https://aka.ms/byoaks-foundry-registration) may help locate its owner, but is not a current public deployment contract.

As of the documentation check on **25 November 2026**, the public [hosted-agent documentation](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents) describes Microsoft-managed hosting, image/protocol requirements and agent versions. It does **not** verify the earlier lab's `Management center > Compute clusters` / `Agent hosting > AKS compute` menu paths, automatic AI Manager reuse, or an azd prompt offering your cluster. Those instructions are deliberately not presented as runnable steps.

If approved for own-AKS hosting:

1. Obtain current preview-specific instructions, supported region/cluster versions and identity/RBAC requirements from the preview owner.
2. Confirm whether inference compute and agent hosting are separate attachments and how to select the intended cluster. Do not silently create a second AI Manager or new managed hosting target.
3. Check required agent protocol, health routes, image architecture, registry pull identity, secret handling and private MCP/model reachability. This repo's `/api/troubleshoot` FastAPI contract is **not** automatically a supported Foundry agent protocol; adapting it is a separate implementation exercise.
4. Review incremental compute, logging, model and networking costs before deployment. Targeting a Kata pool must be explicitly supported/configured, not assumed.
5. Follow the approved deployment procedure. Verify an agent version exists, invoke its actual endpoint and verify the resulting workload is on the intended AKS cluster. Preserve the CPU deployment until this works.

**No approval or missing UI?** Stop this optional exercise and continue with the working browser app. Do not substitute managed hosted agents or Azure Machine Learning AKS compute and claim that they demonstrate the same hosting path.

## 4. Carry forward and troubleshoot

| Observation | Interpretation / action |
|---|---|
| Project exists but no registered agent | Expected baseline; inspect the AKS app separately. |
| No own-AKS control | Check preview eligibility/current instructions, not just CLI version. |
| Hosted image cannot start | Verify protocol and image requirements; don't assume an arbitrary FastAPI image is sufficient. |
| Empty tracing view | Go to [module 07](07-observability-cost.md); the shipped dependencies do not provide OpenAI GenAI spans. |

**Checkpoint:** explain which service owns the model endpoint and which owns the agent Deployment. Record whether hosting was actually exercised or only discussed. [Module 04](04-flex-nodes.md) next adds a different kind of compute: a host joined to the plant cluster.
