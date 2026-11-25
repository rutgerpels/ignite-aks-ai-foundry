# 05 - Kata pod isolation and the Agent Sandbox extension

**Session ref:** ~20:00-24:00, isolated execution boundaries.

[Previous: edge compute](04-flex-nodes.md) | [Portal equivalent: stage 7](00-portal-guide.md#7-inspect-kata-then-decide-on-agent-sandbox) | [Next: governed networking](06-agent-grid.md)

**Learn:** pod kernel isolation is different from allocating an execution environment per task. The baseline uses a long-running Deployment with `runtimeClassName: kata-vm-isolation`; it does not allocate SandboxClaims for troubleshooting sessions.

**Before:** module 01's agents cluster and kubeconfig. Flex and GPU modules are not prerequisites for this inspection. The optional extension has additional, stricter requirements below.

## 1. Inspect baseline isolation

Run in PowerShell:

```powershell
$k = '--kubeconfig', '.kube/agents'
kubectl @k get runtimeclass
kubectl @k get nodes -L sandbox,kubernetes.azure.com/agentpool
kubectl @k -n caldova get pod -l app=caldova-agent -o jsonpath='{.items[0].spec.runtimeClassName}{"\n"}{.items[0].spec.nodeName}{"\n"}'

kubectl @k -n caldova exec deploy/caldova-agent -- uname -r
$node = kubectl @k -n caldova get pod -l app=caldova-agent -o jsonpath='{.items[0].spec.nodeName}'
kubectl @k get node $node -o jsonpath='{.status.nodeInfo.kernelVersion}{"\n"}'
kubectl @k -n caldova exec deploy/mcp-plant-signals -- uname -r
```

1. Confirm the pod selects the `kata` pool and the intended RuntimeClass.
2. Inspect that RuntimeClass's handler with `kubectl @k get runtimeclass kata-vm-isolation -o yaml`.
3. Compare guest and assigned-node kernel information. Different versions support the observation of a separate guest kernel, but version strings alone are not an isolation attestation. The MCP pod can run on a different node; compare its own node if investigating its kernel.

**Expected:** the baseline agent uses its requested legacy Kata runtime on the sandbox pool. Portal workload/pool YAML can show configuration; execution commands collect runtime evidence. Keep container limits: Kata uses them to size its micro-VM. See [pod sandboxing](https://learn.microsoft.com/azure/aks/use-pod-sandboxing) and current SKU/OS constraints before changing capacity.

## 2. Agent Sandbox extension (preview)

The current [Agent Sandbox guide](https://learn.microsoft.com/azure/aks/agent-sandbox-cluster-extension) offers different runtime paths. This lab discusses the **Kata** path, not the separate ACI-powered serverless path. An extension installation supports only one runtime.

**Stop gate:** the Kata walkthrough requires managed-identity AKS **Kubernetes 1.35+**, Pod sandboxing with **Kata VM isolation v2**, regional availability (check AKS release `1025`), Azure CLI **2.85.0+**, `k8s-extension`, and registered `Microsoft.KubernetesConfiguration`. AKS Automatic is not supported. The shipped legacy RuntimeClass and `workloadRuntime: KataVmIsolation` pool property do **not** establish these conditions.

1. Read the guide's **Prepare your AKS cluster** section. Have the cluster owner approve compatible capacity or a distinct replacement pool if required. Do not relabel old nodes or modify the working Deployment to pretend it has v2.
2. Verify the genuine runtime and pool nodes, using the target pool name from that approved setup:

   ```powershell
   $rg = azd env get-value AZURE_RESOURCE_GROUP
   $aks = azd env get-value AKS_AGENTS_NAME
   $pool = '<verified-v2-pool-name>'
   az aks show -g $rg -n $aks --query currentKubernetesVersion -o tsv
   az aks nodepool show -g $rg --cluster-name $aks -n $pool `
     --query "{runtime:workloadRuntime,os:not_null(osSku,osSKU),size:vmSize,count:count,image:nodeImageVersion}" -o json
   kubectl @k get runtimeclass kata-vm-isolation-v2 -o jsonpath='{.handler}{"\n"}'
   kubectl @k get nodes -l "kubernetes.azure.com/kata-vm-isolation-v2=true,agentpool=$pool"
   ```

   Require handler **`kata-v2`**, matching labeled node count equal to pool count, at least one node, and all target nodes Ready. If no nodes match or a runtime is missing, **stop**; a feature flag alone does not fix existing nodes. Follow the guide's current preparation/reconciliation and readiness checks.
3. Only after those checks pass, install and verify the extension:

   ```powershell
   az extension add --name k8s-extension --upgrade
   az k8s-extension create -g $rg --cluster-name $aks --cluster-type managedClusters `
     --name agent-sandbox --extension-type Microsoft.AgentSandbox
   az k8s-extension show -g $rg --cluster-name $aks --cluster-type managedClusters `
     --name agent-sandbox --query "{state:provisioningState,version:currentVersion}"
   kubectl @k -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=5m
   kubectl @k api-resources --api-group=agents.x-k8s.io
   ```

   Require `Succeeded`, extension **1.0.7+**, a ready controller and served Sandbox API `v1beta1`. Installing the extension does not enable the node runtime. The former guessed `az aks update --enable-agent-sandbox` is not the documented cluster-extension path.
4. Create an isolated **test** environment using the guide's current `Sandbox` manifest. For example, submit the following through portal **Create > Apply a YAML**, or save it outside tracked manifests and apply with `kubectl @k apply -f <file>`:

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

   Use an organization-approved/pinned image where required. Image-pull access and capacity are additional prerequisites.
5. Inspect the Sandbox conditions/events and resulting pod, then verify its runtime and execute only a harmless kernel check:

   ```powershell
   kubectl @k -n agent-demo get sandboxes,pods -o wide
   kubectl @k -n agent-demo describe sandbox python-runner
   kubectl @k -n agent-demo get pods -o yaml
   # Replace with the resulting pod name after it is Ready:
   kubectl @k -n agent-demo exec <sandbox-pod> -- python -c "import platform; print(platform.release())"
   ```

**Expected:** a ready Sandbox-backed pod on genuine v2 capacity, independent of the existing Caldova Deployment. CRD presence alone is not enough. For warm pools/claims use the guide's **current** `extensions.agents.x-k8s.io/v1beta1` examples; the old v1alpha1 template is not a safe default.

**Limits and cost:** extra pools and warm pools incur capacity costs while idle. Pod snapshot is a separate optional extension with stricter image/node-count constraints; it is not installed here. Creating a Sandbox does not wire the agent to execute each task inside it, nor does kernel isolation prevent every prompt-injection or network attack.

## Troubleshoot and finish

| Symptom | Check |
|---|---|
| RuntimeClass missing / pod Pending | Supported regional release, v2 handler, genuine node labels, capacity and events; never spoof labels. |
| Unknown resource/API version | Extension state/version, controller and served CRDs against current guide. |
| Image pull fails | Image permission, approved outbound path and registry access. |
| v2 unavailable | Keep baseline Kata and skip the extension; record the unmet prerequisite. |

Delete the test Sandbox and namespace after inspection, only if created for this exercise. Coordinate extension/pool deletion with the owner and [module 08](08-cleanup.md). Do not remove shared runtime capacity.

**Carry forward:** compute isolation evidence, separate from the network/tool authorization demonstrated in [module 06](06-agent-grid.md).
