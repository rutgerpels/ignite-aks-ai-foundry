# 05 – Sandboxed agents: Kata pod sandboxing and the Agent Sandbox extension

**Session ref:** ~20:00–24:00 ("sandboxing capabilities ... each agent its own isolated boundary").

Agents run code and call tools. Giving them their own kernel limits the blast radius. The lab's `aks-agents-*` cluster has a `kata` node pool (`workloadRuntime: KataVmIsolation`, Azure Linux). `azd up` already deployed the Caldova agent with `runtimeClassName: kata-vm-isolation`.

## 1. Show the isolation

```powershell
$k = '--kubeconfig', '.kube/agents'
kubectl @k get runtimeclass
kubectl @k get nodes -L sandbox,kubernetes.azure.com/agentpool
kubectl @k -n caldova get pod -l app=caldova-agent -o jsonpath='{.items[0].spec.runtimeClassName}{"\n"}{.items[0].spec.nodeName}{"\n"}'

# Kernel inside the pod (the Kata guest kernel) vs the node kernel
kubectl @k -n caldova exec deploy/caldova-agent -- uname -r
$node = kubectl @k -n caldova get pod -l app=caldova-agent -o jsonpath='{.items[0].spec.nodeName}'
kubectl @k get node $node -o jsonpath='{.status.nodeInfo.kernelVersion}{"\n"}'
```

The two kernel versions differ, so the agent runs in its own micro-VM. Compare with an MCP server pod (regular runc), which reports the node kernel:

```powershell
kubectl @k -n caldova exec deploy/mcp-plant-signals -- uname -r
```

Notes:
- Kata sizes the micro-VM from the container **limits**, so always set them.
- Requirements: Azure Linux node OS, Gen2 VM with nested virtualization (DSv5 works), no Trusted Launch.
- `KataVMIsolationV2Preview` enables the v2 runtime on **new** pools if the flag was registered before the pool was created.

## 2. Agent Sandbox extension (preview)

The Agent Sandbox extension adds the open-source [agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) CRDs (`Sandbox`, `SandboxTemplate`, `SandboxClaim`, `SandboxWarmPool`). With them you get on-demand, stateful, single-pod sandboxes with a stable identity, fast start-up from warm pools, and Kata isolation. This is how an agent gets a fresh "computer" per task or session.

Follow the official guide at **https://aka.ms/aks/agent-sandbox** (needs the `AgentSandboxPreview` flag). The pattern for the lab cluster:

```powershell
$rg = azd env get-value AZURE_RESOURCE_GROUP
$aks = azd env get-value AKS_AGENTS_NAME
# Enable (check the guide for the exact command/extension type in your CLI version)
az aks update -g $rg -n $aks --enable-agent-sandbox
kubectl @k get crd | Select-String sandbox
```

Then create a sandbox template that uses Kata, plus a claim:

```yaml
apiVersion: extensions.agents.x-k8s.io/v1alpha1
kind: SandboxTemplate
metadata: { name: python-runner, namespace: caldova }
spec:
  podTemplate:
    spec:
      runtimeClassName: kata-vm-isolation
      nodeSelector: { sandbox: kata }
      containers:
        - name: runner
          image: python:3.12-slim
          command: ["sleep", "infinity"]
          resources: { limits: { cpu: "1", memory: 1Gi } }
---
apiVersion: extensions.agents.x-k8s.io/v1alpha1
kind: SandboxClaim
metadata: { name: rca-session-line7, namespace: caldova }
spec:
  sandboxTemplateRef: { name: python-runner }
```

```powershell
kubectl @k -n caldova get sandboxes,sandboxclaims
kubectl @k -n caldova exec -it <sandbox-pod> -- python -c "import platform; print(platform.release())"
```

> API groups and versions change between preview drops. If `kubectl apply` fails, run `kubectl explain sandboxtemplate` against your cluster and adjust.

Demo talking point: in "autonomous" mode the Caldova agent chooses which tools to call. Run each session in its own claimed sandbox, so a prompt-injected tool output can't reach the node or other tenants.
