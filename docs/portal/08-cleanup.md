# 08 - Clean up and verify deletion

[Previous: evidence and cost](07-observability-cost.md) | [Portal experience](README.md) | [Lab home](../../README.md)

**Learn:** teardown follows resource dependencies, including optional resources not tracked by the base deployment. An accepted deletion request or stopped VM is not proof that charges have ended.

**Before:** save nonsecret learning results and inventory every resource created. Confirm the subscription, names, owners and whether you are deleting the whole disposable lab or only an optional exercise. Deletion is destructive. Do not remove locks, deny assignments or governance policies to force it.

**Surface:** Azure portal for Azure/Kubernetes resource deletion. Local azd state, kubeconfigs, SSH keys and bootstrap files need a separate local review. Do not run `azd down` concurrently with portal deletion.

## 1. Decide what to retain

1. Open the base lab resource group and inspect its contents.
2. List optional resources outside it: separate GPU group and manager-owned groups, Grid/policy groups, Content Safety, new v2 capacity and approved hosting connections.
3. If retaining the CPU app but deleting its GPU model, perform the rollback below **before** removing inference.
4. If deleting the full lab, stop using its endpoints and continue with the dependency order below.

### Roll back GPU chat when retaining the CPU app

On the **agents cluster** in namespace `caldova`:

1. Open **Kubernetes resources > Configuration > agent-config** and restore module 02's recorded CPU `LLM_BASE_URL` and `LLM_MODEL`.
2. Keep the CPU `VISION_BASE_URL`, `VISION_API_KEY: not-needed` and `VISION_MODEL: moondream` intact.
3. Under **Workloads**, edit Deployment `caldova-agent`. Remove only the `LLM_API_KEY` env entry that references `llm-key`; retain other environment settings.
4. Change `spec.template.metadata.annotations.lab.caldova/restarted-at` to a new quoted UTC timestamp to trigger a rollout. Preserve other annotations and labels.
5. Wait for a Ready replacement pod, check `/api/config`, then run Guided and Inspect.
6. Only after no workload references it, delete the unused `llm-key` Secret. Do not delete shared Secrets.

If rollback fails, resolve the configuration/network issue before deleting the model still in use.

## 2. Remove optional consumers and attachments

1. **Foundry:** if you actually created hosted agents/versions or own-AKS attachments, remove them through the current approved preview procedure. The base app is not a Foundry hosted agent.
2. **Sandbox:** on the appropriate agents cluster, delete only test Sandboxes/claims/warm pools and the disposable `agent-demo` namespace created for this exercise. Coordinate extension/new-pool deletion with the owner after removing consumers; preserve shared runtime capacity.
3. **Grid:** open **Grid members > Members**, unenroll the lab workloads, then **Attached resources**, detach the cluster. Do this **before cluster deletion**.
4. Delete the lab Grid when no longer used. Review and remove unused lab-specific **policy-group resources separately**; they are independent of the Grid. Preserve shared policies, Content Safety and logging resources.
5. **Flex:** if keeping the host or cluster, use the current [Flex host/machine removal procedure](https://learn.microsoft.com/azure/aks/manage-and-remove-flex-nodes) before deleting its pool/identity assignment. The full-lab teardown below deletes only the disposable lab VM and cluster, not a real on-premises host. Remove the `plant2` test workload/namespace if retaining the cluster.

**Checkpoint:** no retained consumer relies on an endpoint, attachment, runtime or identity you are about to delete.

## 3. Remove AI Manager resources deliberately

1. Open **Kubernetes center > AI workloads > AI/ML > Deployments** and identify the correct manager/deployment.
2. For model-only cleanup, use the model deployment's documented deletion operation rather than deleting the entire manager/cluster.
3. For full manager cleanup, select the AI Manager and **Delete AI Manager**. Read its resource deletion summary before confirming.
4. For a manager attached to the shared baseline inference cluster, **do not assume cluster retention**. Deletion policy determines its impact. Preserve the baseline if continuing the lab.
5. For a separate Malaysia West test, identify its manager-created cluster and managed groups; inspect deletion results and ownership. Do not stop after deleting the model while leaving unintended chargeable infrastructure running.
6. Wait for manager/model deletion to finish. Inspect any operation error rather than repeatedly submitting deletes.

**Expected:** intended model/manager resources are gone, and any retained compute is deliberate and recorded. A GPU group created separately is not removed by the base azd environment.

## 4. Delete dedicated groups

1. In **Resource groups**, select the separate GPU-test group, if created, and review all resources/owners.
2. Once its dependencies are handled, choose **Delete resource group**, enter the requested name and confirm. Do not delete an arbitrary managed group as a shortcut around its owning service.
3. For full lab teardown, repeat the review/deletion for the **base lab group**.
4. Wait for the portal's deletion result. Inspect and resolve any denied/failed operation with the owner; do not remove governance controls.
5. Refresh the resource list. Check the owning services and their AKS-managed resource groups for residual resources outside the deleted groups.

Use the **one** chosen cleanup route. Portal deletion does not update local azd environment state or purge every soft-deleted resource. Do not follow it with a blind forced purge.

## 5. Verify cloud and local completion

| Check | Done when |
|---|---|
| Base group, if deleted | Refresh/search confirms it is gone, not merely "deleting". |
| Optional resources | GPU/manager/cluster, Grid/independent policies, extra capacity, disks/IPs and other owned resources are removed or intentionally retained. |
| Retained/soft-deleted services | Retention and any approved purge are understood; no assumption that names are immediately reusable. |
| Cost analysis | After billing catches up, no unintended continuing resources remain. Historical charges are expected. |
| Local files | Sensitive temporary files and obsolete access material have been reviewed separately. |

For local cleanup, remove only known lab artifacts you no longer need: repo `.kube` and `.flex` files, the WSL `ignite-flex.env`, dedicated bootstrap downloads/token files, and obsolete local `.azure` environment state. Inspect exact paths and ownership first. Do not delete shared credentials, your whole SSH directory or another environment's files.

The generated `~/.ssh/ignite_lab` key pair is separate; remove it only if no retained host uses it. Keep `/etc/aks-flex-node` while an edge host remains attached because its running agent needs that configuration.

Feature registrations are subscription-wide. Unregister only with the subscription owner's approval after checking other workloads; do not bulk-unregister features to clean up one lab.

## Troubleshooting and finish

| Symptom | Action |
|---|---|
| Deletion blocked | Inspect operation errors and ask the resource/governance owner; do not remove locks/policy yourself. |
| Model gone but compute remains | Review manager deletion policy, retained cluster and separate managed groups. |
| Portal resources gone but azd still lists the environment | Expected local-state mismatch; review/remove obsolete local state, not redeploy the lab. |
| Charges still visible | Historical data/ingestion lag versus a continuing resource; inspect inventory before claiming zero cost. |

**Final checkpoint:** intended deletions confirmed, retained resources intentional, sensitive temporary material handled, and any remaining costs/limitations recorded. This completes the portal experience without visiting a code-track module.

**References:** [AI Manager model lifecycle](https://learn.microsoft.com/azure/aks/ai-manager/manage-deployments), [Grid cleanup](https://learn.microsoft.com/azure/agent-grid/configure-agent-grid#clean-up-resources), [Flex removal](https://learn.microsoft.com/azure/aks/manage-and-remove-flex-nodes).
