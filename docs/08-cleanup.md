# 08 – Clean-up

Delete the preview resources you created yourself first, so they don't block resource group deletion:

```powershell
$rg = azd env get-value AZURE_RESOURCE_GROUP
# AI Manager (module 02)
az aimanager list -g $rg -o table
az aimanager delete -g $rg -n <ai-manager-name> --yes
# Flex node pool (module 04): optional, it goes with the cluster
az aks nodepool delete -g $rg --cluster-name (azd env get-value AKS_PLANT_NAME) -n plant2edge --no-wait
```

Remove the Foundry AKS compute / hosted agents you created in the portal (module 03), then:

```powershell
azd down --purge --force
```

`--purge` also purges the soft-deleted Foundry (Cognitive Services) account and Key Vault-backed items, so you can redeploy with the same names.

Optional: unregister preview feature flags (they're harmless if left in place), and delete the local files `.kube/`, `.flex/` and the WSL `~/.config/aks-flexnode/ignite-flex.env`.
