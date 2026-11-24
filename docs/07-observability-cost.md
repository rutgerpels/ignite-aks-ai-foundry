# 07 – Observability and cost

**Session ref:** ~30:00–34:00 ("observable, auditable, leveraging the infrastructure you already own").

## Agent traces in Application Insights / Foundry

The agent sends OpenTelemetry (requests, logs, exceptions) to `appi-*` when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set. `deploy-apps.ps1` sets it automatically. The response trace in the UI lists each MCP tool call with its latency.

> **Optional gen_ai spans:** if you add `opentelemetry-instrumentation-openai-v2` to `src/agent/requirements.txt`, `app.py` instruments the OpenAI client and emits `gen_ai.*` spans with prompts and token usage. This beta package is currently incompatible with the OTel version that `azure-monitor-opentelemetry` pins. The agent detects that and skips it.

1. Run a troubleshoot in the UI.
2. Azure portal → `appi-*` → **Transaction search** → filter on cloud role `caldova-agent`.
3. Foundry portal → your project → **Tracing** → connect the same App Insights resource. The traces now show up in Foundry, even though the agent runs on AKS.

KQL (Log Analytics `log-*`):

```kusto
AppDependencies
| where AppRoleName == "caldova-agent" and TimeGenerated > ago(1h)
| summarize calls=count(), p95=percentile(DurationMs,95) by Name
| order by calls desc
```

## Cluster and model metrics

- Container insights is enabled on all clusters (`omsagent`): Azure portal → AKS → **Monitoring → Insights**.
- Model server: `kubectl --kubeconfig .kube/inference -n inference top pod`. A CPU model shows clearly why GPUs and AI Manager's sizing (`az aimanager model calculate-cost`) matter.
- AI Manager deployments expose Prometheus metrics (tokens/s, queue depth) through the managed gateway. See module 02.

## Cost

| Resource | Lab sizing | Tip |
|---|---|---|
| aks-inference | 1× D4s_v5 system + 1× CPU model pool node (`cpuModelVmSize`) | GPU pools only when you have quota |
| aks-agents | 1× D4s_v5 system + 1× Kata node (`kataVmSize`) | |
| aks-plant | 1× D4s_v5 | |
| vm-plant2-edge | D4s_v5 | |
| Foundry, ACR (Basic), Log Analytics | low/usage-based | |

Stop the clusters and the VM between sessions:

```powershell
$rg = azd env get-value AZURE_RESOURCE_GROUP
az aks list -g $rg --query [].name -o tsv | ForEach-Object { az aks stop -g $rg -n $_ --no-wait }
az vm deallocate -g $rg -n (azd env get-value EDGE_VM_NAME) --no-wait
```

Start them again with `az aks start` and `az vm start`. A flex node reconnects automatically after the VM starts.
