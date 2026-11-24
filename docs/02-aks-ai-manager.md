# 02 – AKS AI Manager (models on your own AKS)

**Session ref:** 06:10–08:30 ("AKS AI Manager ... connecting the dots from Foundry managed service to AKS").

AI Manager is an ARM API (`Microsoft.ContainerService/aiManagers`) that installs and operates an open-source inference stack (model serving, LLM gateway, autoscaling) on an AKS cluster, so you don't wire up Helm charts yourself. It exposes **namespaces**, each with an OpenAI-compatible gateway endpoint and keys.

## What the lab gives you

`aks-inference-*` is built to meet the bring-your-own-cluster requirements:

| Requirement | Lab setting |
|---|---|
| Same region as the AI Manager | swedencentral |
| Kubernetes RBAC | enabled |
| System-assigned managed identity | yes |
| Azure CNI + **Cilium** dataplane | overlay + Cilium |

## Steps

```powershell
$rg   = azd env get-value AZURE_RESOURCE_GROUP
$aks  = azd env get-value AKS_INFERENCE_ID
$loc  = 'swedencentral'

# 1. Create the AI Manager attached to the existing cluster
az aimanager create -g $rg -n aim-caldova -l $loc --cluster-id $aks
az aimanager show   -g $rg -n aim-caldova -o table

# 2. Look at what was installed on the cluster
az aks get-credentials -g $rg -n (azd env get-value AKS_INFERENCE_NAME) --admin -f .kube/inference --overwrite-existing
kubectl --kubeconfig .kube/inference get ns
kubectl --kubeconfig .kube/inference get pods -A | Select-String -NotMatch 'kube-system'

# 3. Create a namespace (a tenant/team boundary with its own gateway keys)
az aimanager namespace create -g $rg -m aim-caldova -n line-troubleshooting --labels team=manufacturing
az aimanager namespace list-accesskeys -g $rg -m aim-caldova -n line-troubleshooting
```

### Browse the catalog and estimate cost

```powershell
az aimanager model list -l $loc -o table
az aimanager model show -l $loc -n <model-name>
az aimanager model calculate-cost -l $loc -n <model-name>
```

Discuss with the audience: which VM size the model needs, replica cost per hour, versus pay-per-token in Foundry.

### (Optional) Bring your own model source

```powershell
# e.g. a Hugging Face token so gated open-weight models can be pulled
az aimanager modelsource create -g $rg -m aim-caldova -n hf --source-type HuggingFace --token <hf_token>
```

### Deploy a model (needs GPU quota)

```powershell
$modelId = az aimanager model show -l $loc -n <model-name> --query id -o tsv
az aimanager namespace modeldeployment create -g $rg -m aim-caldova --ns line-troubleshooting `
  -n qwen-chat --model-resource-id $modelId --vm-size Standard_NC24ads_A100_v4 --min-replicas 1 --max-replicas 2
```

> **No GPU quota?** Model deployments require a GPU VM size, so skip this. The lab runs the same *pattern* on CPU with Ollama (`k8s/inference/ollama.yaml`): an OpenAI-compatible endpoint on the inference cluster consumed by the agent.

### Point the agent at the AI Manager gateway

Once a deployment is running, swap the agent's model endpoint – no code change, it's OpenAI-compatible:

```powershell
$keys = az aimanager namespace list-accesskeys -g $rg -m aim-caldova -n line-troubleshooting -o json | ConvertFrom-Json
kubectl --kubeconfig .kube/agents -n caldova patch configmap agent-config --type merge -p (@{data=@{
  LLM_BASE_URL = "<endpoint from list-accesskeys>/v1"; LLM_MODEL = 'qwen-chat' }} | ConvertTo-Json -Compress)
kubectl --kubeconfig .kube/agents -n caldova create secret generic llm-key --from-literal=LLM_API_KEY=<key> --dry-run=client -o yaml | kubectl --kubeconfig .kube/agents apply -f -
kubectl --kubeconfig .kube/agents -n caldova rollout restart deploy/caldova-agent
```

(Add an `envFrom: secretRef: llm-key` to `k8s/agent/agent.yaml` if you use a key.)

## RBAC

| Role | Purpose |
|---|---|
| Azure AIManager Contributor | create/update managers, namespaces, deployments |
| Azure AIManager Model User | call model endpoints with Entra ID |

## Clean up this module

```powershell
az aimanager delete -g $rg -n aim-caldova --yes
```
