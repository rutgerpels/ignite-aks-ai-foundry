# 05 - Inspect Kata isolation and optionally create a Sandbox

[Previous: plant compute](04-flex-nodes.md) | [Portal experience](README.md) | [Next: governed networking](06-agent-grid.md)

**Learn:** kernel isolation is different from allocating an execution environment per task. The base agent is one long-running Deployment with the legacy `kata-vm-isolation` runtime; it does not allocate SandboxClaims per troubleshooting request.

**Before:** module 01's working agents cluster and authorized Kubernetes access. GPU, Foundry hosting and Flex are not required. The optional Sandbox exercise has stricter runtime/version/capacity gates below.

**Surfaces:** Azure portal for pool/workload/YAML inspection, local PowerShell for runtime evidence and extension setup. All commands target **agents**, not the plant cluster used in module 04.

## 1. Inspect baseline configuration visually

1. Open `aks-agents-*` in Azure portal and inspect its **Node pools**. Locate the `kata` pool and its VM/runtime configuration.
2. Open **Kubernetes resources > Workloads**, namespace `caldova`, Deployment `caldova-agent`.
3. Inspect its YAML: `runtimeClassName: kata-vm-isolation`, node selector `sandbox: kata`, and container resource requests/limits. Kata uses those limits when sizing the micro-VM.
4. Inspect the running pod's assigned node and compare it with the Kata pool. The YAML request and actual placement are separate observations.

**Expected:** the baseline app uses its intended legacy Kata pool. A `KataVmIsolation` pool property alone does not distinguish legacy from v2 capability.

## 2. Collect runtime evidence

Run **local PowerShell 7 from the repository root**, using module 01's agents kubeconfig:

```powershell
$k = '--kubeconfig', '.kube/agents'
kubectl @k get runtimeclass kata-vm-isolation -o yaml
kubectl @k get nodes -L sandbox,kubernetes.azure.com/agentpool
kubectl @k -n caldova get pods -l app=caldova-agent -o wide
kubectl @k -n caldova exec deployment/caldova-agent -- uname -r
$node = kubectl @k -n caldova get pod -l app=caldova-agent -o jsonpath='{.items[0].spec.nodeName}'
kubectl @k get node $node -o jsonpath='{.status.nodeInfo.kernelVersion}{"\n"}'
```

Different guest/node kernel versions support the observation of a separate guest kernel; matching or different version strings alone are not a security attestation. Do not compare with an unrelated MCP node and call that proof.

**Baseline checkpoint:** requested runtime, pool placement and runtime evidence recorded. You can now continue to module 06 without installing Sandbox.

## 3. Decide whether the optional Kata v2 path is eligible

This module covers the **Kata** runtime path, not the distinct ACI-powered serverless path. Each extension installation supports only one runtime.

Require all of the following before installation:

| Requirement | What to verify |
|---|---|
| Cluster | Managed identity, Kubernetes 1.35+, not AKS Automatic |
| Region | Kata v2 rollout, AKS release `1025` in the [release tracker](https://releases.aks.azure.com/AKSRelease) |
| Tools/access | Azure CLI 2.85.0+, `k8s-extension`, registered `Microsoft.KubernetesConfiguration`, necessary roles |
| Runtime | RuntimeClass `kata-vm-isolation-v2` with handler **`kata-v2`** |
| Capacity | Genuine v2-capable Azure Linux nodes, all target nodes labeled by the platform and Ready |
| Budget | Approved additional capacity; idle pools/Sandboxes still cost money |

The shipped legacy pool does not establish these conditions. **Do not manually label old nodes to fake v2 support or change the working agent to an unavailable runtime.**

If existing approved v2 capacity is present, skip pool creation. Otherwise the cluster owner must approve a distinct replacement/test pool and a supported available SKU. This is additional infrastructure, not an automatic migration of the baseline.

**Optional, only after approval and regional/tool checks**, in local PowerShell:

```powershell
$rg = azd env get-value AZURE_RESOURCE_GROUP
$aks = azd env get-value AKS_AGENTS_NAME
$pool = 'katav2'
$size = '<approved-available-kata-v2-sku>'
az aks nodepool add -g $rg --cluster-name $aks -n $pool --mode User --os-sku AzureLinux `
  --workload-runtime KataVmIsolation --node-vm-size $size --node-count 1
az aks update -g $rg -n $aks
```

For existing v2 capacity initialize the variables without creating anything:

```powershell
$rg = azd env get-value AZURE_RESOURCE_GROUP
$aks = azd env get-value AKS_AGENTS_NAME
$pool = '<existing-verified-v2-pool-name>'
```

Run only the relevant capacity option. Do not create a duplicate pool. Installing the extension will not configure the node runtime for you.

Verify the actual runtime and every node in the selected pool:

```powershell
az aks show -g $rg -n $aks --query currentKubernetesVersion -o tsv
az aks nodepool show -g $rg --cluster-name $aks -n $pool `
  --query "{runtime:workloadRuntime,os:not_null(osSku,osSKU),count:count,image:nodeImageVersion}" -o json
kubectl @k get runtimeclass kata-vm-isolation-v2 -o jsonpath='{.handler}{"\n"}'
az aks nodepool show -g $rg --cluster-name $aks -n $pool --query count -o tsv
kubectl @k get nodes -l "kubernetes.azure.com/kata-vm-isolation-v2=true,agentpool=$pool" `
  -o go-template='{{len .items}}{{"\n"}}'
kubectl @k wait --for=condition=Ready nodes `
  -l "kubernetes.azure.com/kata-vm-isolation-v2=true,agentpool=$pool" --timeout=5m
```

Require handler `kata-v2`, at least one node, matching configured/labeled node counts, AzureLinux and all nodes Ready. If these conditions fail, **stop this optional exercise**. Preserve baseline Kata and record the missing prerequisite.

## 4. Install and verify the extension

Only after section 3 passes, run in the same **local PowerShell** session:

```powershell
az extension add --name k8s-extension --upgrade
az k8s-extension create -g $rg --cluster-name $aks --cluster-type managedClusters `
  --name agent-sandbox --extension-type Microsoft.AgentSandbox
az k8s-extension show -g $rg --cluster-name $aks --cluster-type managedClusters `
  --name agent-sandbox --query "{state:provisioningState,version:currentVersion}"
kubectl @k -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=5m
kubectl @k api-resources --api-group=agents.x-k8s.io
```

Require `Succeeded`, extension **1.0.7+**, a ready controller and served Sandbox API `agents.x-k8s.io/v1beta1`. An older successful extension or CRD alone is not enough.

## 5. Create and inspect a disposable Sandbox in the portal

On the **agents cluster**, use **Create > Apply a YAML** to submit:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: agent-demo
---
apiVersion: agents.x-k8s.io/v1beta1
kind: Sandbox
metadata:
  name: python-runner
  namespace: agent-demo
spec:
  podTemplate:
    metadata:
      labels:
        app: python-runner
    spec:
      enableServiceLinks: false
      runtimeClassName: kata-vm-isolation-v2
      containers:
        - name: runner
          image: python:3.12-slim
          command: ["sleep", "infinity"]
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits: { cpu: "1", memory: 1Gi }
```

Use an organization-approved/pinned image if required. Inspect an existing `agent-demo` namespace before reusing it.

1. In **Custom resources**, find Sandbox `python-runner` in `agent-demo`; inspect status conditions and events.
2. In **Workloads**, inspect its backing pod. Confirm runtime `kata-vm-isolation-v2`, Ready state and placement on genuine v2 capacity.
3. Collect the harmless runtime check in local PowerShell:

   ```powershell
   kubectl @k -n agent-demo wait --for=condition=Ready sandbox/python-runner --timeout=5m
   kubectl @k -n agent-demo get pods -l app=python-runner -o wide
   kubectl @k -n agent-demo exec <resulting-pod-name> -- python -c "import platform; print(platform.release())"
   ```

**Expected:** one ready Sandbox-backed pod, independent of the existing Caldova Deployment. This does not wire the app to create per-session SandboxClaims or prevent every prompt/network attack. Warm pools and Pod snapshot are separate optional capabilities; they are not installed/exercised here.

## Troubleshooting and carry forward

| Symptom | Check |
|---|---|
| Missing RuntimeClass / Pending pod | Regional v2 support, actual pool image/capability, node counts and events; never spoof labels. |
| Unknown resource/version | Extension state/version, controller and served CRDs. |
| Image pull fails | Image permission, registry reachability and approved egress. |
| v2 not available or too expensive | Keep baseline Kata, skip Sandbox and continue the lab. |

In the portal delete only the disposable Sandbox and its `agent-demo` namespace when finished, after checking ownership. Coordinate removal of any additional test extension/pool with the owner and module 08; do not remove shared/legacy capacity.

**Carry forward:** baseline isolation evidence, optional Sandbox result or explicit skip reason, and any extra resources to clean up. [Module 06](06-agent-grid.md) adds network/tool authorization, which kernel isolation does not supply.

**References:** [Pod sandboxing](https://learn.microsoft.com/azure/aks/use-pod-sandboxing), [Agent Sandbox extension and current Kata v2 preparation](https://learn.microsoft.com/azure/aks/agent-sandbox-cluster-extension).
