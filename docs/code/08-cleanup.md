# 08 - Cleanup and verify

[Previous: evidence and cost](07-observability-cost.md) | [Code experience](README.md) | [Lab home](../../README.md)

**Learn:** teardown follows resource dependencies, including optional resources not tracked by azd. Stopping compute is not deletion.

**Before:** save nonsecret learning results and inventory everything created in modules 02-06, including resources outside the main lab group. Confirm subscription, azd environment and group contain **only disposable lab resources**. Deletion is destructive; do not remove locks, deny assignments or governance policies to force it.

## 1. Remove optional consumers and attachments first

1. If retaining the CPU app, roll it back from AI Manager before deleting the model (module 02). For full teardown, stop using its endpoints.
2. Remove optional hosted agents/versions and own-AKS attachments using the approved preview instructions from module 03. The base app is not a Foundry hosted agent.
3. Delete module 05's disposable test Sandboxes/claims/warm pools and workloads, if created, before removing their extension/capacity. Do not delete shared pools/extensions.
4. For Agent Grid, **unenroll AKS workloads and detach the cluster before cluster deletion**. Delete the lab Grid and then unused policy-group resources; policy groups are independent resources. Preserve shared policies and Content Safety/log resources. See [Grid cleanup](https://learn.microsoft.com/azure/agent-grid/configure-agent-grid#clean-up-resources).
5. Remove Flex validation workloads and follow the current [Flex documentation](https://learn.microsoft.com/azure/aks/attach-flex-node-to-aks) for host/machine lifecycle if preserving the host or cluster. This full-lab teardown deletes the disposable VM and cluster, not a production/on-prem host.

## 2. Review and remove AI Manager

```powershell
$rg = azd env get-value AZURE_RESOURCE_GROUP
az account show --query "{subscription:id,tenant:tenantId}" -o table
az aimanager list -g $rg -o table
```

This first list covers the **base group only**. If module 02 used a separate GPU group/region, also list managers in that recorded group and use its actual name for model cleanup; do not assume azd tracks it.

Inspect the intended manager and deletion policy before proceeding. A manager can own/manage compute; deletion impact depends on configuration. The portal's **AI/ML > Deployments > Delete AI Manager** shows a summary. If you only want to remove a model, use [deployment-only deletion](https://learn.microsoft.com/azure/aks/ai-manager/manage-deployments#delete-a-model-deployment) instead.

Once its full deletion impact is approved:

```powershell
az aimanager delete -g <actual-manager-resource-group> -n <ai-manager-name> --yes
# Optional pool-only deletion; unnecessary if deleting the entire plant cluster:
az aks nodepool delete -g $rg --cluster-name (azd env get-value AKS_PLANT_NAME) -n plant2edge --no-wait
```

Replace placeholders and wait for deletions to finish before proceeding. Do not run these commands against a manager/pool you skipped creating.

## 3. Delete the separate GPU group, if created

After model/manager deletion and review of its owned cluster/managed groups, remove the disposable GPU group only if it contains nothing to retain:

```powershell
az group delete -n <recorded-gpu-test-group> --yes
az group exists -n <recorded-gpu-test-group>
```

Expect `false` after completion. Inspect residual owner-managed resources and deletion errors; do not delete arbitrary managed groups to bypass a service. Skip this section if you reused the baseline inference cluster. Do not use the GPU group as the target of later base-environment commands.

## 4. Delete the base: choose one route

**Code route:** from the repo root, verify `azd env list` selects the intended environment, review the target inventory, then:

```powershell
azd down --purge --force
```

`--force` skips confirmation and `--purge` requests permanent deletion of supported soft-deleted resources. Use only after reviewing targets; it is not a guarantee that every external or retained resource is removed. Do not purge shared data/services or assume resource names are immediately reusable.

**Portal route:** open the dedicated lab resource group in Azure portal, review its resources/dependencies, choose **Delete resource group**, enter the requested name and confirm. Inspect the deletion result. Check AKS-managed groups and optional resources outside the group separately; portal deletion does not update local azd environment state or automatically purge all soft-deleted services. Do not run portal and azd teardown concurrently.

## 5. Verify completion

1. Refresh the Azure resource list and verify the lab group and its owned resources are gone. CLI equivalent for the main group:

   ```powershell
   az group exists --name $rg
   ```

   Expect `false` after deletion, not just an accepted delete request.
2. Check managed node groups, optional GPU/Grid/policy resources, disks, IPs and retained/soft-deleted items. If deletion is blocked, inspect operation errors and ask the owner; do not remove governance.
3. Revisit Cost analysis after billing data catches up. Historical charges remain visible; look for unintended continuing resources.
4. Remove only known local lab artifacts you no longer need: `.kube`, `.flex`, WSL `~/.config/aks-flexnode/ignite-flex.env`, temporary bootstrap/token files and downloads. Consider local `.azure` state and lab-generated `~/.ssh/ignite_lab` keys separately; never delete shared credentials or your whole SSH directory.
5. Feature registrations are subscription-wide. Unregister only with the subscription owner's approval and after checking other workloads; do not bulk-unregister shared features.

**Done when:** deletion is confirmed, remaining retained resources are intentional, sensitive temporary files are handled, and any residual cost/preview limitations are recorded.
