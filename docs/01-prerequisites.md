# 01 – Prerequisites and preview access

Most capabilities shown in BRK420 are **preview** (some **limited preview**). Do this first; some approvals take days.

## Tools

| Tool | Version used |
|---|---|
| Azure CLI | 2.80+ |
| `aks-preview` extension | 22.0.0b8 or later (`az extension add -n aks-preview --upgrade`) |
| `aimanager` extension | 2.0.1b4 or later (`az extension add -n aimanager --upgrade`) |
| Azure Developer CLI (azd) | 1.20+ |
| kubectl | 1.30+ |
| PowerShell 7 (or bash) | for the scripts |

No local Docker is needed: images are built with `az acr build`.

## Feature flags (self-service)

```powershell
$flags = 'AIManagerPreview','AKSFlexNodePreview','PutMachinePreview','KataVMIsolationPreview','KataVMIsolationV2Preview','AgentSandboxPreview'
foreach ($f in $flags) { az feature register --namespace Microsoft.ContainerService --name $f -o none }
# wait until every flag reports "Registered"
foreach ($f in $flags) { az feature show --namespace Microsoft.ContainerService --name $f --query "{name:name,state:properties.state}" -o tsv }
az provider register -n Microsoft.ContainerService
az provider register -n Microsoft.KubernetesConfiguration
az provider register -n Microsoft.CognitiveServices
```

> `KataVMIsolationV2Preview` must be **Registered before** a Kata node pool is created if you want the v2 runtime. The lab uses the GA `KataVmIsolation` runtime, so this is optional.

## Limited-preview sign-ups (manual approval)

| Capability | Where |
|---|---|
| Foundry models & hosted agents on your own AKS ("AKS compute") | https://aka.ms/byoaks-foundry-registration |
| Agent Grid | https://learn.microsoft.com/azure/agent-grid/overview (request access link on the page) |

Until approved, the matching portal options are hidden. The rest of the lab still works.

## Quota

The lab deploys **CPU only** (no GPU quota needed): ~26 vCPU of DSv5 in `swedencentral`.

```powershell
az vm list-usage -l swedencentral --query "[?contains(name.value,'DSv5')]" -o table
```

If you do have GPU quota (e.g. `Standard_NC24ads_A100_v4`), module 02 shows how to deploy a real catalog model through AI Manager.

## Deploy the base environment

```powershell
azd auth login            # or: azd config set auth.useAzCliAuth true
azd env new ignite-aks
azd env set AZURE_LOCATION swedencentral
azd up
```

`preprovision` creates `~/.ssh/ignite_lab` and detects your public IP for the edge VM NSG. `postprovision` builds the images and deploys the sample (`scripts/deploy-apps.ps1`).
