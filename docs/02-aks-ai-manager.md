# 02 – AKS AI Manager (models on your own AKS)

**Session ref:** 06:10–08:30 ("AKS AI Manager ... connecting the dots from Foundry managed service to AKS").

AI Manager is an ARM API (`Microsoft.ContainerService/aiManagers`) that installs and operates an open-source inference stack (model serving, LLM gateway, autoscaling) on an AKS cluster, so you don't wire up Helm charts yourself. It exposes **namespaces**, each with an OpenAI-compatible gateway endpoint and keys.

[Previous: baseline](01-prerequisites.md) | [Portal equivalent: stage 4](00-portal-guide.md#4-deploy-and-test-a-gpu-model-in-azure-portal) | [Next: Foundry boundary](03-foundry-aks-compute.md)

**Learn:** replace CPU inference while retaining the browser agent and MCP tools from module 01. AI Manager has a documented **Azure portal** catalog/deploy/test/manage path; it is not command-only and is not the separate KAITO AI toolchain operator. Check the [current quickstart](https://learn.microsoft.com/azure/aks/ai-manager/quickstart) and [deployment management](https://learn.microsoft.com/azure/aks/ai-manager/manage-deployments).

**Before:** working Guided CPU baseline, registered AI Manager preview/provider, appropriate AI Manager roles, supported region/catalog model, model-license acceptance and approved GPU quota/budget. Without those, keep Ollama and skip GPU creation.

## What the lab gives you

`aks-inference-*` is built to meet the bring-your-own-cluster requirements:

| Requirement | Lab setting |
|---|---|
| Same region as the AI Manager | azd region (`swedencentral` by default) |
| Kubernetes RBAC | enabled |
| System-assigned managed identity | yes |
| Azure CNI + **Cilium** dataplane | overlay + Cilium |

## Steps

```powershell
$rg   = azd env get-value AZURE_RESOURCE_GROUP
$aks  = azd env get-value AKS_INFERENCE_ID
$loc  = azd env get-value AZURE_LOCATION

# 1. Create the AI Manager attached to the existing cluster
az aimanager create -g $rg -n aim-caldova -l $loc --cluster-id $aks
az aimanager show   -g $rg -n aim-caldova -o table

# 2. Look at what was installed on the cluster
az aks get-credentials -g $rg -n (azd env get-value AKS_INFERENCE_NAME) --admin -f .kube/inference --overwrite-existing
kubectl --kubeconfig .kube/inference get ns
kubectl --kubeconfig .kube/inference get pods -A | Select-String -NotMatch 'kube-system'

# 3. Create a namespace (a tenant/team boundary with its own gateway keys)
az aimanager namespace create -g $rg --aimanager aim-caldova -n line-troubleshooting --labels team=manufacturing
# Returns secrets: inspect privately, never copy into Git/screenshots.
az aimanager namespace list-accesskeys -g $rg --aimanager aim-caldova -n line-troubleshooting
```

### Browse the catalog and estimate cost

```powershell
az aimanager model list -l $loc -o table
az aimanager model show -l $loc -n <model-name>
az aimanager model calculate-cost -l $loc -n <model-name>
```

Discuss with the audience: which VM size the model needs, replica cost per hour, versus pay-per-token in Foundry.

### (Optional) Bring your own model source

Only if your chosen model requires it, use an approved secret-handling process for the token. Do not paste a real token into a shared shell or save it in this document:

```powershell
# e.g. a Hugging Face token so gated open-weight models can be pulled
az aimanager modelsource create -g $rg --aimanager aim-caldova -n hf --source-type HuggingFace --token <hf_token>
```

For a deployment that needs this source, retrieve its resource ID and supply `--model-source-resource-id` as described in the [modelsource reference](https://learn.microsoft.com/cli/azure/aimanager/modelsource). Creating an unused source does not change the default catalog deployment below.

### Deploy a model (needs GPU quota)

```powershell
$modelId = az aimanager model show -l $loc -n <model-name> --query id -o tsv
az aimanager namespace modeldeployment create -g $rg --aimanager aim-caldova --namespace line-troubleshooting `
  -n qwen-chat --model-resource-id $modelId --vm-size Standard_NC24ads_A100_v4 --min-replicas 1 --max-replicas 2
```

Replace angle-bracket placeholders and the example GPU SKU with a feasible catalog plan. The cost calculator estimates **VM cost per replica**, not full deployment/lab cost. Two replicas can increase cost. Wait for `provisioningState: Succeeded` and ready replicas, then test a chat request using the quickstart before changing the app:

```powershell
az aimanager namespace modeldeployment show -g $rg --aimanager aim-caldova `
  --namespace line-troubleshooting -n qwen-chat -o json
```

> **No GPU quota?** Skip creation. The lab runs the same *endpoint-consumption pattern*, not AI Manager itself, on CPU with Ollama (`k8s/inference/ollama.yaml`, namespace `models`).

### Point the agent at the AI Manager gateway

1. In the same PowerShell session, record the current endpoint/model for rollback. Start from the module 01 CPU baseline. Keep the vision endpoint on Ollama: its default otherwise follows the chat endpoint.
2. Retrieve namespace credentials without printing them. Use the returned endpoint **as supplied**: do not append another `/v1` (see [endpoint guidance](https://learn.microsoft.com/azure/aks/ai-manager/connect-to-endpoint)).
3. Apply the config and secret and reference the secret in the Deployment. Kubernetes Secrets are not a vault; use an approved terminal/secret-handling process, not shared shell history or screenshots.

```powershell
$oldConfig = kubectl --kubeconfig .kube/agents -n caldova get configmap agent-config -o json | ConvertFrom-Json
$keys = az aimanager namespace list-accesskeys -g $rg --aimanager aim-caldova -n line-troubleshooting -o json | ConvertFrom-Json
if (-not $oldConfig.data.LLM_BASE_URL -or -not $keys.endpoint -or -not $keys.primaryKey) {
  throw 'Missing baseline configuration or namespace credentials; stop before changing the app.'
}
kubectl --kubeconfig .kube/agents -n caldova patch configmap agent-config --type merge -p (@{data=@{
  LLM_BASE_URL = $keys.endpoint; LLM_MODEL = 'qwen-chat'
  VISION_BASE_URL = $oldConfig.data.LLM_BASE_URL; VISION_API_KEY = 'not-needed'
}} | ConvertTo-Json -Compress)
@{
  apiVersion = 'v1'; kind = 'Secret'
  metadata = @{name='llm-key'; namespace='caldova'}
  type = 'Opaque'; stringData = @{LLM_API_KEY=$keys.primaryKey}
} | ConvertTo-Json -Depth 4 -Compress | kubectl --kubeconfig .kube/agents apply -f -
kubectl --kubeconfig .kube/agents -n caldova set env deployment/caldova-agent --from=secret/llm-key
kubectl --kubeconfig .kube/agents -n caldova rollout restart deploy/caldova-agent
kubectl --kubeconfig .kube/agents -n caldova rollout status deploy/caldova-agent --timeout=10m
Remove-Variable keys
```

4. Open `/api/config` in the app browser to confirm endpoint/model, then rerun Guided and Autonomous against the module 01 baseline. Check Inspect still uses Ollama. A ready pod alone does not verify inference.

**Troubleshooting:** 401/403 → credential/auth mode and roles; provisioning failure → full deployment/events and quota/capacity; connection timeout → approved routes and baseline NetworkPolicy. That policy allows the inference subnet on 11434 and public HTTPS, not every possible gateway destination/port. Have the platform owner review required connectivity; do not disable policies. `scripts/deploy-apps.ps1` reapplies baseline ConfigMap values, so record/reapply intentional preview overrides after a redeploy.

**Rollback:** restore `$oldConfig.data.LLM_BASE_URL` and `.LLM_MODEL` in the ConfigMap, remove the Deployment's `LLM_API_KEY` override (`kubectl --kubeconfig .kube/agents -n caldova set env deployment/caldova-agent LLM_API_KEY-`), restart and verify Guided again. Remove the now-unused `llm-key` Secret only after no workload references it.

## RBAC

| Role | Purpose |
|---|---|
| Azure AIManager Contributor | create/update managers, namespaces, deployments |
| Azure AIManager Model User | catalog reads and cost calculation, normally at subscription scope |
| Azure AIManager Inference User | namespace API key retrieval and direct Entra ID inference at namespace scope |

These are distinct permissions; the base deployment does not automatically grant them. The sample uses a namespace API key, not an Entra token provider. Ask an authorized role administrator for the narrowest approved assignments; see [Grant access](https://learn.microsoft.com/azure/aks/ai-manager/grant-access).

## Clean up this module

If continuing the CPU lab, roll the app back first. Review AI Manager's cluster deletion policy/summary before removing it: this exercise attached a shared lab cluster. Do not delete the manager while assuming it will always leave compute untouched. Use deployment-only deletion from the linked management guide when appropriate.

```powershell
az aimanager delete -g $rg -n aim-caldova --yes
```
