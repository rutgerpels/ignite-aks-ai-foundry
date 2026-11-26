# 02 – AKS AI Manager (models on your own AKS)

**Session ref:** 06:10–08:30 ("AKS AI Manager ... connecting the dots from Foundry managed service to AKS").

AI Manager is an ARM API (`Microsoft.ContainerService/aiManagers`) that installs and operates an open-source inference stack (model serving, LLM gateway, autoscaling) on an AKS cluster, so you don't wire up Helm charts yourself. It exposes **namespaces**, each with an OpenAI-compatible gateway endpoint and keys.

[Previous: baseline](01-prerequisites.md) | [Code experience](README.md) | [Next: Foundry boundary](03-foundry-aks-compute.md)

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

## 1. Select the inference location

Keep the module 01 baseline and azd environment unchanged. Choose **one** option below. All commands run in PowerShell 7 from the repository root.

**Option A - reuse the baseline inference cluster in its own region:**

```powershell
$rg   = azd env get-value AZURE_RESOURCE_GROUP
$aks  = azd env get-value AKS_INFERENCE_ID
$loc  = azd env get-value AZURE_LOCATION
$manager = 'aim-caldova'

az aimanager create -g $rg -n $manager -l $loc --cluster-id $aks --delete-policy Keep
```

`Keep` preserves the shared inference cluster when this manager is removed. For an existing manager, inspect its current deletion policy rather than assuming it was created with this setting.

**Option B - create a separate GPU tier, for example in Malaysia West:**

Use this only when that region offers your exact catalog model/SKU, sufficient quota and an approved budget. An ordinary AKS pool cannot be added in a different region to a Swedish cluster. The new AI Manager creates its own cluster and associated billable resources.

```powershell
$rg = 'rg-ignite-gpu-malaysia'  # choose a new dedicated test group
$loc = 'malaysiawest'
$manager = 'aim-caldova-my'
az group create -g $rg -l $loc
az aimanager create -g $rg -n $manager -l $loc
```

Do not run both options, change `AZURE_LOCATION` in the existing environment, or run the entire Bicep deployment to move inference. Keep Foundry, agents and plant resources in their original region. Agent Grid availability is separate and requires the Grid and attached compute to share a supported region.

For either option, record `$rg`, `$loc` and `$manager` for all later model operations and cleanup. They can differ from azd's baseline group. Do not rerun creation if the intended manager already exists.

## 2. Inspect and create a namespace

```powershell
az aimanager show -g $rg -n $manager -o table
```

**Option A only:** inspect the existing inference cluster:

```powershell
az aks get-credentials -g $rg -n (azd env get-value AKS_INFERENCE_NAME) --admin -f .kube/inference --overwrite-existing
kubectl --kubeconfig .kube/inference get ns
kubectl --kubeconfig .kube/inference get pods -A | Select-String -NotMatch 'kube-system'
```

**Option B:** inspect the manager-owned cluster in its resource group instead; do not overwrite `.kube/inference` with credentials for a different cluster.

For either option, create a namespace, a tenant/team boundary with its own gateway keys:

```powershell
az aimanager namespace create -g $rg --aimanager $manager -n line-troubleshooting --labels team=manufacturing
# Returns secrets: inspect privately, never copy into Git/screenshots.
az aimanager namespace list-accesskeys -g $rg --aimanager $manager -n line-troubleshooting
```

## 3. Browse the catalog and estimate cost

```powershell
az aimanager model list -l $loc -o table
$modelName = '<catalog-resource-name>'  # Name, not the readable modelId
az aimanager model show -l $loc -n $modelName
az aimanager model calculate-cost -l $loc -n $modelName -o table
```

Choose your exact model/SKU combination, not merely a model with a similar name. For example, `Qwen/Qwen3.5-4B` can be a candidate to inspect; do not assume its current plan is available for every subscription. Quota approval is not an allocation guarantee. If portal and CLI plans disagree, check the exact model/region and current preview version before creating resources; record the discrepancy rather than silently selecting a larger VM.

There is no verified documented Spot selection in the AI Manager workflow used here. Do not assume the calculator's prices or a portal deployment are Spot prices. Review VM cost per replica, CPU system capacity, disks, networking and monitoring; short tests still cost money. Budget alerts are not spending caps.

### (Optional) Bring your own model source

Only if your chosen model requires it, use an approved secret-handling process for the token. Do not paste a real token into a shared shell or save it in this document:

```powershell
# e.g. a Hugging Face token so gated open-weight models can be pulled
az aimanager modelsource create -g $rg --aimanager $manager -n hf --source-type HuggingFace --token <hf_token>
```

For a deployment that needs this source, retrieve its resource ID and supply `--model-source-resource-id` as described in the [modelsource reference](https://learn.microsoft.com/cli/azure/aimanager/modelsource). Creating an unused source does not change the default catalog deployment below.

## 4. Deploy and test one replica

```powershell
$vmSize = '<vm-size-from-approved-feasible-plan>'
$modelId = az aimanager model show -l $loc -n $modelName --query id -o tsv
az aimanager namespace modeldeployment create -g $rg --aimanager $manager --namespace line-troubleshooting `
  -n qwen-chat --model-resource-id $modelId --vm-size $vmSize --replicas 1
```

Replace the placeholders before execution; do not automatically substitute an A100 or other expensive SKU. The calculator estimates **VM cost per replica**, not full deployment/lab cost. Keep one fixed replica for this test. Wait for `provisioningState: Succeeded` and one ready replica:

```powershell
az aimanager namespace modeldeployment show -g $rg --aimanager $manager `
  --namespace line-troubleshooting -n qwen-chat -o json

$keys = az aimanager namespace list-accesskeys -g $rg --aimanager $manager -n line-troubleshooting -o json | ConvertFrom-Json
if (-not $keys.endpoint -or -not $keys.primaryKey) { throw 'Missing endpoint or key; stop.' }
$request = @{model='qwen-chat';messages=@(@{role='user';content='What does Kubernetes do?'})} | ConvertTo-Json -Depth 4
Invoke-RestMethod -Method Post -Uri "$($keys.endpoint.TrimEnd('/'))/chat/completions" `
  -Headers @{Authorization="Bearer $($keys.primaryKey)"} -ContentType 'application/json' -Body $request
Remove-Variable keys
```

Expect response text under `choices[0].message.content`. A ready model and a reachable endpoint are separate checkpoints. Keep credentials private. For a separate-region tier, test from an authorized client before considering the app cutover.

> **No GPU quota?** Skip creation. The lab runs the same *endpoint-consumption pattern*, not AI Manager itself, on CPU with Ollama (`k8s/inference/ollama.yaml`, namespace `models`).

## 5. Point the agent at the AI Manager gateway

For a separate-region deployment, first have the platform owner verify routes, DNS, approved endpoint exposure and the agent's NetworkPolicy. Its baseline permits the original private inference subnet on TCP 11434 and public HTTPS, not an arbitrary new private gateway. Cross-region traffic can add latency and charges. If connectivity is not approved/working, keep this as a standalone playground/inference test and retain CPU chat.

1. In the same PowerShell session, record the current endpoint/model for rollback. Start from the module 01 CPU baseline. Keep the vision endpoint on Ollama: its default otherwise follows the chat endpoint.
2. Retrieve namespace credentials without printing them. Use the returned endpoint **as supplied**: do not append another `/v1` (see [endpoint guidance](https://learn.microsoft.com/azure/aks/ai-manager/connect-to-endpoint)).
3. Apply the config and secret and reference the secret in the Deployment. Kubernetes Secrets are not a vault; use an approved terminal/secret-handling process, not shared shell history or screenshots.

```powershell
$oldConfig = kubectl --kubeconfig .kube/agents -n caldova get configmap agent-config -o json | ConvertFrom-Json
$keys = az aimanager namespace list-accesskeys -g $rg --aimanager $manager -n line-troubleshooting -o json | ConvertFrom-Json
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

If continuing the CPU lab, roll the app back first. Review AI Manager's cluster deletion policy/summary before removing it: option A attached a shared lab cluster, while option B created separate compute. Do not assume deletion always leaves compute untouched. Use deployment-only deletion from the linked management guide when appropriate. For option B, include its separate group/managed resources in module 08; azd does not track them.

```powershell
az aimanager delete -g $rg -n $manager --yes
```

**Carry forward:** baseline and GPU observations, model deployment name, nonsecret manager/group/region, approved connectivity and rollback settings. Continue to [module 03](03-foundry-aks-compute.md) even if this optional GPU exercise was skipped.
