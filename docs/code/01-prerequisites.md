# 01 – Prerequisites and preview access

Most capabilities shown in BRK420 are **preview** (some **limited preview**). Do this first; some approvals take days.

[Code experience](README.md) | [Next: models](02-aks-ai-manager.md)

**Learn:** establish access and a working CPU baseline before changing model/hosting/network layers. Use a dedicated approved lab subscription/resource group. You need permissions to deploy the resources, register selected features/providers, and create role assignments (for example Owner, or Contributor plus Role Based Access Control Administrator at the necessary scope). AKS Kubernetes access is separate from Azure resource access. Do not deploy production data into this unauthenticated demo.

**Before:** obtain the subscription owner's permission and a budget for disposable lab resources, then complete the tool, access and quota checks below before deploying.

## Tools

| Tool | Version used |
|---|---|
| Azure CLI | 2.80+ |
| `aks-preview` extension | 22.0.0b8 or later (`az extension add -n aks-preview --upgrade`) |
| `aimanager` extension | current preview (`az extension add -n aimanager --upgrade --allow-preview true`) |
| Azure Developer CLI (azd) | 1.20+ |
| kubectl | 1.30+ |
| PowerShell 7 | required for `deploy-apps.ps1`, including on Linux; Bash alone is not sufficient |

No local Docker is needed: images are built with `az acr build`.

The versions above describe the original base track, not a guarantee for every current preview. Agent Sandbox's current Kata guide requires **Azure CLI 2.85.0+**, `k8s-extension`, Kubernetes 1.35+ and verified Kata v2 support. Follow module 04's linked articles for current Flex versions. Confirm `az version`, `azd version`, `kubectl version --client` and `$PSVersionTable.PSVersion` before starting.

## Feature flags (self-service)

Register only features required for the modules you will run. This preserves the original full-lab command sequence; registration can require approval and is a subscription-level change. Azure portal also supports registration under **Subscriptions > Settings > Preview features**, but not every service exposes every flag there.

```powershell
$flags = 'AIManagerPreview','AKSFlexNodePreview','PutMachinePreview','KataVMIsolationPreview','KataVMIsolationV2Preview','AgentSandboxPreview'
foreach ($f in $flags) { az feature register --namespace Microsoft.ContainerService --name $f -o none }
# wait until every flag reports "Registered"
foreach ($f in $flags) { az feature show --namespace Microsoft.ContainerService --name $f --query "{name:name,state:properties.state}" -o tsv }
az provider register -n Microsoft.ContainerService
az provider register -n Microsoft.KubernetesConfiguration
az provider register -n Microsoft.CognitiveServices
```

> A registered flag does not prove runtime capability. The base workload uses `kata-vm-isolation`; the current Agent Sandbox Kata path needs verified **v2** RuntimeClass and node support. Complete [module 05's gates](05-pod-sandboxing-agent-sandbox.md#2-agent-sandbox-extension-preview) before attempting it. If a flag is `Pending`, obtain approval; wait for feature and provider registration to finish.

## Limited-preview sign-ups (manual approval)

| Capability | Where |
|---|---|
| Foundry models & hosted agents on your own AKS ("AKS compute") | https://aka.ms/byoaks-foundry-registration |
| Agent Grid | https://learn.microsoft.com/azure/agent-grid/overview (request access link on the page) |

Missing options can also mean wrong tenant, insufficient RBAC, unsupported region or a changed preview UI. The Foundry own-AKS registration link is historical; confirm current onboarding with the preview owner rather than assuming menu labels. Agent Grid also requires its own provider/features and compatible cluster: see [module 06](06-agent-grid.md). The CPU app does not depend on these two limited previews.

## Quota

The lab deploys **CPU only** (no GPU quota needed): ~26 vCPU of DSv5 in `swedencentral`.

Default sizing: inference D4 + D8, agents D4 + D4, plant D2, edge D4. Check total regional and family quotas, region/SKU availability and budget **before** `azd up`. This is not a free lab: nodes, disks, load balancers, public IPs, registry and logs cost money even without GPU models. GPU replicas and optional replacement/sandbox pools add cost; budget alerts are not spending caps.

```powershell
az vm list-usage -l swedencentral --query "[?contains(name.value,'DSv5')]" -o table
```

If you have GPU quota and an approved budget, module 02 shows how to choose a feasible catalog plan and deploy one replica through AI Manager. A GPU is optional, not a requirement for this baseline.

## Deploy the base environment

1. Clone/open this repo and run commands from its root in PowerShell 7. Select the intended subscription for Azure CLI and azd prompts; check `az account show --query "{subscription:id,tenant:tenantId}"`.
2. Run the sequence below once for a **new** environment. Choose an unused azd environment name and a region that meets the modules you intend to run. For an existing lab, use `azd env list` and `azd env select <existing-name>`, inspect its resources, then resume at the checkpoint instead. Do not change the existing environment's region to relocate it.
3. Inspect any failed deployment operation and resolve the cause before retrying. Do not create replacement portal clusters alongside this deployment.

```powershell
azd auth login            # or: azd config set auth.useAzCliAuth true
azd env new ignite-aks
azd env set AZURE_LOCATION swedencentral
azd up
```

`preprovision` creates `~/.ssh/ignite_lab` and detects your public IP for the edge VM NSG. `postprovision` builds the images and deploys the sample (`scripts/deploy-apps.ps1`).

## Checkpoint and recovery

```powershell
kubectl --kubeconfig .kube/inference -n models rollout status deployment/ollama --timeout=10m
kubectl --kubeconfig .kube/inference -n models wait --for=condition=complete job/pull-models --timeout=20m
kubectl --kubeconfig .kube/agents -n caldova get pods,services
azd env get-value AGENT_URL
```

Open the browser app, run **Guided** on line-7, and retain duration/model/tool results as your baseline. `aks-plant-*` can remain NotReady until module 04 installs its CNI; inference and agents should not.

| Symptom | Next check |
|---|---|
| Deployment or role assignment denied | Azure deployment operations, effective roles, preview registration and Azure Policy with the owner. Do not remove policy. |
| Pending/image-pull/model errors | Pod events and `kubectl --kubeconfig .kube/inference -n models logs job/pull-models`; quotas, ACR permissions and download access. |
| Credentials denied | Hooks use `--admin` for this lab. If local accounts/admin credentials are prohibited, stop and arrange approved Kubernetes access; do not enable them to bypass policy. |
| Public demo or SSH blocked | Effective NSG/routing rules may be governance-managed. Use the approved access procedure below, not rule deletion. |

### Approved application access

The sample is unauthenticated HTTP with fictional data. If its public URL times out, inspect Service endpoints, pod readiness and effective routes/NSGs with the platform owner. Do not remove managed controls. Where organizational policy permits it, an authorized workstation with Kubernetes API access can forward the app locally:

```powershell
kubectl --kubeconfig .kube/agents -n caldova port-forward service/caldova-agent 8080:80 --address 127.0.0.1
```

Keep the terminal open and browse `http://127.0.0.1:8080`; Ctrl+C ends the forward. This is not a permission bypass. Cloud Shell's localhost is not your workstation's localhost.

**Carry forward:** `.kube/inference`, `.kube/agents`, your azd environment and baseline results. Kubeconfigs/keys are sensitive; do not commit them. [Module 02](02-aks-ai-manager.md) changes the model layer, not the MCP tool chain. [Cleanup](08-cleanup.md) applies even after a partial deployment.
