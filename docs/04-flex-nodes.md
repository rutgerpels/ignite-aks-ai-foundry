# 04 – Flex nodes: bring Plant 2's edge server into AKS

**Session ref:** ~15:00–19:00 ("heterogeneous infrastructure ... multiple plants ... some things on-prem").

Flex nodes (preview) let you join a Linux machine you own and run (on-premises, another cloud, or an Azure VM) to an AKS node pool. AKS manages the control plane; you manage the host and network. In the lab:

| Story | Lab resource |
|---|---|
| Plant 2 edge server | `vm-plant2-edge` (Ubuntu 24.04) in `vnet-plant2` 10.20.0.0/16 |
| Plant network ↔ cloud | VNet peering (stands in for VPN/ExpressRoute) |
| AKS cluster for the plant | `aks-plant-*`: created with `networkPlugin: none`, as the Learn walkthrough requires |
| Host identity | user-assigned identity `id-vm-plant2-edge` on the VM |

> The flex walkthrough installs **Unbounded-Net** as the cluster CNI, so it uses its own cluster. The inference and agent clusters keep Azure CNI + Cilium, which AI Manager needs.
>
> Before you start, the plant cluster's single node is **NotReady**. That's expected: it has no CNI until you install Unbounded-Net.

## Address plan used by the lab

| Variable | Value |
|---|---|
| `AKS_SUBNET_CIDR` / `AKS_NODE_CIDR` | 10.10.8.0/24 |
| `AKS_POD_CIDR` | 10.100.0.0/16 |
| `FLEX_HOST_SUBNET_CIDR` / `FLEX_NODE_CIDR` | 10.20.1.0/24 |
| `FLEX_POD_CIDR` | 10.101.0.0/16 |
| `SERVICE_CIDR` / `DNS_SERVICE_IP` | 10.110.0.0/16 / 10.110.0.10 |

## 0. Prepare a Bash environment

The Learn articles use Bash. On Windows, use **WSL (Ubuntu)**, with `az`, `aks-preview`, `kubectl`, `jq`, `curl` and `sha256sum` installed. The edge VM NSG only allows SSH from the public IP you deployed from. If you use another machine, update the NSG rule `allow-ssh-from-operator` in `nsg-plant2-edge`.

Generate the shared environment file from your azd outputs (PowerShell, in the repo root):

```powershell
./scripts/new-flex-env.ps1
```

Then, in WSL:

```bash
REPO=/mnt/c/path/to/ignite-aks-ai-foundry          # adjust
install -D -m 0600 "$REPO/.flex/ignite-flex.env" ~/.config/aks-flexnode/ignite-flex.env
install -D -m 0600 /mnt/c/Users/$USER/.ssh/ignite_lab ~/.ssh/ignite_lab     # adjust Windows user name
install -D -m 0644 /mnt/c/Users/$USER/.ssh/ignite_lab.pub ~/.ssh/ignite_lab.pub

export FLEXNODE_DEPLOYMENT="ignite-flex"
export FLEXNODE_ENV_FILE="${HOME}/.config/aks-flexnode/${FLEXNODE_DEPLOYMENT}.env"
source "${FLEXNODE_ENV_FILE}"
install -d -m 0700 "${WORK_DIR}"
az login && az account set --subscription "${SUBSCRIPTION_ID}"
az extension add -n aks-preview --upgrade
ssh -i "${SSH_PRIVATE_KEY_PATH}" "${FLEX_HOST_SSH_TARGET}" hostname   # -> vm-plant2-edge
```

> **Versions:** the Learn articles pin compatible versions of `AKS_VERSION`, `UNBOUNDED_VERSION` and `AKS_FLEX_NODE_VERSION`. The generated file uses the plant cluster's current version. If the docs require a different one (e.g. `1.36.2`), upgrade the plant cluster first:
> `az aks upgrade -g $RESOURCE_GROUP -n $CLUSTER_NAME -k <version> --yes`. Then update `AKS_VERSION` with `set_flexnode_env AKS_VERSION <version>`.
> Also check that the region runs AKS release **v20260904 or later** in the [release tracker](https://releases.aks.azure.com/AKSRelease).

## 1. Prepare the cluster

Follow [Prepare an AKS cluster for flex nodes](https://learn.microsoft.com/azure/aks/prepare-aks-cluster-for-flex-nodes), but **skip cluster creation**: `aks-plant-*` already exists with the required network profile. Do the parts that fetch the dedicated kubeconfig and record `FLEXNODE_KUBECONFIG`:

```bash
export FLEXNODE_KUBECONFIG="${WORK_DIR}/kubeconfig"
az aks get-credentials -g "${RESOURCE_GROUP}" -n "${CLUSTER_NAME}" --admin -f "${FLEXNODE_KUBECONFIG}" --overwrite-existing
chmod 0600 "${FLEXNODE_KUBECONFIG}"
set_flexnode_env FLEXNODE_KUBECONFIG "${FLEXNODE_KUBECONFIG}"
export KUBECONFIG="${FLEXNODE_KUBECONFIG}"
kubectl get nodes      # 1 node, NotReady (no CNI yet)
```

## 2. Networking and flex node pool

Follow [Configure networking and create a flex node pool](https://learn.microsoft.com/azure/aks/configure-flex-nodes-networking) as written. In summary:

```bash
# install the kubectl-unbounded plugin (see article), then:
kubectl unbounded install --timeout 5m
kubectl unbounded site init --name flex-site \
  --cluster-node-cidr "${AKS_NODE_CIDR}" --cluster-pod-cidr "${AKS_POD_CIDR}" \
  --node-cidr "${FLEX_NODE_CIDR}" --pod-cidr "${FLEX_POD_CIDR}"
# apply the SitePeering "cluster-flex-private-l3" (meshNodes: true, tunnelProtocol: Auto)
kubectl wait --for=condition=Ready nodes --all --timeout=5m     # AKS node now Ready
# apply the temporary aks-flex-node-daemon ClusterRole/Binding if missing

az aks nodepool add -g "${RESOURCE_GROUP}" --cluster-name "${CLUSTER_NAME}" -n "${FLEX_POOL_NAME}" \
  --vm-set-type FlexNodes --mode User --kubernetes-version "${AKS_VERSION}" \
  --max-pods 75 --max-unavailable 1 \
  --labels pool-generation=initial --node-taints pool-generation=initial:NoSchedule -o none
set_flexnode_env FLEX_POOL_RESOURCE_ID "${AKS_RESOURCE_ID}/agentPools/${FLEX_POOL_NAME}"
```

Teaching point: there's no VM size, count or subnet on a flex pool. It's a logical group for compute you bring.

## 3. Host and identity

Follow [Prepare a flex node host and identity](https://learn.microsoft.com/azure/aks/prepare-flex-node-host-identity) and choose the **Azure VM managed identity → user-assigned** path. The lab already created the identity and attached it to the VM, and `HOST_IDENTITY_CLIENT_ID` / `HOST_PRINCIPAL_OBJECT_ID` are pre-filled. Do the role assignment yourself; it's scoped to the **flex pool**, not the cluster:

```bash
az role assignment create \
  --assignee-object-id "${HOST_PRINCIPAL_OBJECT_ID}" --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Flex Node Agent Role" \
  --scope "${FLEX_POOL_RESOURCE_ID}"
```

Also run the article's host checks: OS, swap off, required kernel modules, time sync, and outbound HTTPS to ARM, Entra ID, the AKS API and GitHub releases.

## 4. Attach

Follow [Attach a flex node to an AKS cluster](https://learn.microsoft.com/azure/aks/attach-flex-node-to-aks), choosing the **Azure VM managed identity** tab and the user-assigned variant:

1. Download `aks-flex-node-linux-amd64.tar.gz`, `checksums.txt` and `bootstrap.sh` for `${AKS_FLEX_NODE_VERSION}`, then verify the checksum.
2. `az aks nodepool get-bootstrap-data ... > ${WORK_DIR}/base-config.json`. The token in this file is valid for one hour.
3. `scp` the files to the VM and install `base-config.json` in `/etc/aks-flex-node/`.
4. On the VM, as root:

   ```bash
   env AKS_FLEX_NODE_BASE_CONFIG_FILE=/etc/aks-flex-node/base-config.json \
     bash /tmp/bootstrap.sh --auth msi --msi-client-id "${HOST_IDENTITY_CLIENT_ID}" \
     --agent-url "file:///tmp/${AGENT_ARCHIVE}" --agent-sha256 "${AGENT_SHA256}"
   ```

## 5. Validate (demo moment)

```bash
kubectl get nodes -L net.unbounded-cloud.io/site,kubernetes.azure.com/agentpool -o wide
az aks machine list -g "${RESOURCE_GROUP}" --cluster-name "${CLUSTER_NAME}" --nodepool-name "${FLEX_POOL_NAME}" -o table
```

Run a "plant-local" workload on the edge node, for example the plant signals MCP server close to the line:

```bash
ACR=$(az acr list -g "${RESOURCE_GROUP}" --query [0].loginServer -o tsv)
az aks update -g "${RESOURCE_GROUP}" -n "${CLUSTER_NAME}" --attach-acr "${ACR%%.*}"
kubectl create ns plant2
kubectl -n plant2 apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: mcp-plant-signals }
spec:
  selector: { matchLabels: { app: mcp-plant-signals } }
  template:
    metadata: { labels: { app: mcp-plant-signals } }
    spec:
      nodeSelector: { kubernetes.azure.com/agentpool: ${FLEX_POOL_NAME} }
      tolerations: [{ key: pool-generation, value: initial, effect: NoSchedule }]
      containers:
        - name: mcp
          image: ${ACR}/caldova-mcp-plant-signals:v1
          ports: [{ containerPort: 8080 }]
EOF
kubectl -n plant2 get pod -o wide        # NODE = vm-plant2-edge
kubectl -n plant2 logs deploy/mcp-plant-signals   # proves the control plane → kubelet path
```

Talking point: the telemetry stays in the plant, while the agent in the cloud calls the tool over the private network.

## Troubleshooting

| Symptom | Check |
|---|---|
| AKS node stays NotReady after Unbounded-Net | CIDRs overlap? `AKS_SUBNET_CIDR` must sit inside `AKS_NODE_CIDR` |
| Bootstrap 401/403 | role on the **pool** scope, propagation (wait 5 min), correct `--msi-client-id` |
| Agent exits, "cache sync" | the temporary `aks-flex-node-daemon` RBAC is missing |
| `kubectl logs` times out | NSG/peering: AKS → node TCP 10250 |
| Agent logs on host | `journalctl -u aks-flex-node-agent -f` |
