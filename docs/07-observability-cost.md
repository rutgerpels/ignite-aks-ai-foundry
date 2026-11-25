# 07 - Observability and cost

**Session ref:** ~30:00-34:00, observable and auditable infrastructure.

[Previous: network evidence](06-agent-grid.md) | [Portal equivalent: stage 9](00-portal-guide.md#9-observe-cost-and-clean-up) | [Next: cleanup](08-cleanup.md)

**Learn:** distinguish a useful browser result, application telemetry, cluster metrics and network-policy logs. Connect these observations to the baseline recorded in module 01 and any changes actually made in modules 02-06.

**Before:** a working agent run, App Insights/Log Analytics access and allowed telemetry egress. Optional Grid evidence requires its diagnostics setting. Missing telemetry is a finding, not permission to change network governance.

## 1. Establish what the agent actually emits

`scripts/deploy-apps.ps1` sets `APPLICATIONINSIGHTS_CONNECTION_STRING` on the agent. `src/agent/app.py` then calls `configure_azure_monitor()` from `azure-monitor-opentelemetry`. Actual collected HTTP requests/dependencies/logs depend on supported instrumentation, sampling and network access.

The shipped `src/agent/requirements.txt` does **not** include `opentelemetry-instrumentation-openai-v2`, following a dependency incompatibility. `app.py` attempts an optional import and reports it disabled when unavailable. Do not promise `gen_ai` spans, prompt content, token telemetry, full MCP child spans or a complete Foundry trace tree. Do not install an incompatible beta package just to make a demonstration match a diagram.

The browser's `tool_calls`/latencies and model `usage` are response JSON assembled by the app. They are **not** manually created OpenTelemetry spans or guaranteed exported metrics.

1. Run Guided on line-7; record UTC time, duration, model and tool-call list from the UI.
2. In Azure portal, open `appi-*` > **Transaction search** for that time window. Look for role/service `caldova-agent`; allow ingestion delay. Inspect a received operation's available dependencies rather than assuming every call is present.
3. In the workspace `log-*`, use **Logs** to inspect actual received dependencies:

   ```kusto
   AppDependencies
   | where AppRoleName == "caldova-agent" and TimeGenerated > ago(1h)
   | summarize calls=count(), p95=percentile(DurationMs,95) by Name
   | order by calls desc
   ```

4. If the query is empty, check requests/logs for the same window and agent logs for configuration/export problems. This diagnostic query can show whether any data arrived:

   ```kusto
   union withsource=SourceTable isfuzzy=true AppRequests, AppDependencies, AppTraces
   | where TimeGenerated > ago(1h)
   | where AppRoleName == "caldova-agent"
   | summarize records=count() by SourceTable
   ```

5. In Foundry, inspect the existing project's monitoring connection. If its tracing experience supports the telemetry actually received, compare it with App Insights. A connection alone does not guarantee visibility of this independently hosted FastAPI app, or turn ordinary HTTP telemetry into GenAI spans.

**Expected:** evidence of whatever Azure Monitor actually collects, with any gaps stated explicitly. GPU-model comparison should use the browser's real model/duration as well as available telemetry, not inferred token statistics.

## 2. Separate cluster health from policy decisions

1. On inference and agents, open Azure portal **Monitoring > Insights** and inspect node/container health. Their templates configure the `omsagent` addon; `aks-plant-*` does **not** configure it.
2. For CPU pressure, use metrics server directly:

   ```powershell
   kubectl --kubeconfig .kube/inference -n models top pod
   ```

   Compare with actual request duration; CPU usage alone does not establish model quality or throughput.
3. For optional AI Manager models, inspect provisioning/replica health in **AI/ML > Deployments** and follow current service documentation for additional metrics. Do not assume a Prometheus scrape/dashboard was provisioned by this repo.
4. For optional Grid, use **Live inspect**, **Flow map** and `AgentFabricFlowLogs` in the selected workspace. They prove policy verdicts, not agent reasoning quality. Use module 06's source/destination/rule correlation.

| Symptom | Check |
|---|---|
| Browser works but no app telemetry | Connection configuration, supported instrumentation, sampling, startup/export logs, ingestion delay and approved Azure Monitor egress. |
| No GenAI spans | Expected with shipped dependencies; do not treat as deployment failure. |
| Plant Insights empty | No Container insights addon is configured there; don't claim it was enabled. |
| Grid logs empty | Enrollment, diagnostic category/workspace and time window; attachment alone is insufficient. |

## 3. Understand the costs you introduced

| Default resource | Sizing / cost consideration |
|---|---|
| Inference | 1x D4s_v5 system + 1x D8s_v5 CPU model node by default; optional GPU replicas add capacity. |
| Agents | 1x D4s_v5 system + 1x D4s_v5 Kata node by default; optional compatible v2 capacity is additional. |
| Plant | 1x D2s_v5, including while its CNI setup is unfinished. |
| Edge VM | 1x D4s_v5 plus disk and public IP. |
| Other | AKS tiers, disks, load balancers, public IPs, ACR Basic, monitoring ingestion/retention, network traffic and optional preview dependencies. |

Open **Cost Management > Cost analysis** at the appropriate subscription scope and group by resource/service for the lab period. Include AKS-managed resource groups and optional resources outside the lab group. Compare AI Manager's calculator only with **VM cost per replica**; it is not a total-cost estimator. There is no fixed price guarantee here.

For a pause, inspect target names and ask the resource owner before stopping anything shared. Azure portal provides AKS stop/start and VM lifecycle controls. Equivalent PowerShell:

```powershell
$rg = azd env get-value AZURE_RESOURCE_GROUP
az aks list -g $rg --query [].name -o tsv
# Only for this dedicated lab group:
az aks list -g $rg --query [].name -o tsv | ForEach-Object { az aks stop -g $rg -n $_ --no-wait }
az vm deallocate -g $rg -n (azd env get-value EDGE_VM_NAME) --no-wait
```

Verify stopped state; for the VM require **Stopped (deallocated)** rather than merely shutting down its guest OS. Storage, IPs, ACR and logs can still charge; check AI Manager-managed GPU compute separately. Start with `az aks start` and `az vm start`, then recheck cluster readiness, Flex agent reconnection, model availability and Guided output rather than promising automatic recovery.

**Carry forward:** baseline/comparison observations, known telemetry gaps, optional-resource inventory and costs. For complete teardown, use [module 08](08-cleanup.md), not Stop alone.
