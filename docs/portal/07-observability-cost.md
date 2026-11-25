# 07 - Observe outcomes and account for cost

[Previous: network policy](06-agent-grid.md) | [Portal experience](README.md) | [Next: cleanup](08-cleanup.md)

**Learn:** browser outcomes, application telemetry, cluster health and policy verdicts are different evidence. Compare only features actually exercised against module 01's baseline, then account for their complete resource footprint.

**Before:** a working app run, App Insights/Log Analytics access and allowed telemetry egress. Optional Grid evidence requires its diagnostic setting; optional GPU comparisons require a successful app cutover. Skipped modules do not prevent baseline monitoring.

**Surfaces:** Caldova browser, Azure Application Insights, Log Analytics, AKS monitoring, optional Grid and Cost Management. KQL is entered directly in the portal's Logs editor.

## 1. Capture a comparable application run

1. Open Caldova through the approved URL/port-forward.
2. Record UTC time, current model/deployment from `/api/config`, selected line, mode, duration and tool-call list.
3. Run **Guided** on line-7, then compare with module 01. If you changed the model, record both quality and time; a faster response is not necessarily a better troubleshooting result.
4. Compare Autonomous separately. Keep Inspect's vision result separate from the chat-model comparison.

UI tool timings and model usage fields are application response JSON. They are **not automatically OpenTelemetry spans or exported token metrics**.

## 2. Inspect what Application Insights actually receives

1. In Azure portal open the baseline `appi-*` resource and **Transaction search**.
2. Select the run's time window and look for role/service `caldova-agent`. Allow ingestion delay.
3. Open an available operation and inspect the request, dependencies and logs that actually arrived. Do not assume every tool/model call has a child span.
4. Open the linked `log-*` Log Analytics workspace > **Logs**. Run:

   ```kusto
   AppDependencies
   | where AppRoleName == "caldova-agent" and TimeGenerated > ago(1h)
   | summarize calls=count(), p95=percentile(DurationMs,95) by Name
   | order by calls desc
   ```

5. To distinguish an empty dependencies table from no application data at all:

   ```kusto
   union withsource=SourceTable isfuzzy=true AppRequests, AppDependencies, AppTraces
   | where TimeGenerated > ago(1h)
   | where AppRoleName == "caldova-agent"
   | summarize records=count() by SourceTable
   ```

6. If no data is received, inspect agent pod startup/export logs, the connection configuration, sampling, ingestion delay and approved Azure Monitor egress with the owner. Do not change governance to make a chart populate.

**Important limitation:** the shipped requirements omit `opentelemetry-instrumentation-openai-v2` after a dependency incompatibility. The app attempts an optional import and reports it disabled when absent. Azure Monitor can collect supported HTTP/log instrumentation, but this lab does **not guarantee** `gen_ai` spans, prompts, token counts, full MCP child spans or a complete Foundry trace tree. Do not install an incompatible beta package to make the view match an expectation.

In Foundry portal inspect the existing project's monitoring connection if desired. A connection is not hosted-agent registration or proof that this independently hosted FastAPI app appears in every Foundry tracing view.

## 3. Separate compute and network evidence

| Surface | Inspect | What it does not prove |
|---|---|---|
| Inference/agents **Monitoring > Insights** | Node/container health and available metrics | Model quality or complete application traces |
| Workload events/logs | Scheduling, image pulls, startup and request errors | Agent Grid policy enforcement |
| AI/ML **Deployments > Check status** | Optional model provisioning, replica and inference health | That Caldova actually switched endpoints |
| Grid **Live inspect / Flow map** | Source, destination, verdict and deciding rule from flow logs | Agent reasoning quality or human approval |
| Plant cluster | Node/workload state from module 04 | Container insights collection: its addon is **not configured** in this repo |

1. Check inference and agents Insights in the same time window as your app test.
2. For optional GPU models, compare actual app endpoint/deployment and browser output with the model's independent health check.
3. For Grid, reuse module 06's timestamps and identity/rule evidence; a browser failure alone remains insufficient.
4. Record absent dashboards/metrics explicitly. The repo does not provision a Prometheus/Grafana model-serving dashboard.

## 4. Review the full cost footprint

1. Open **Cost Management > Cost analysis** at the appropriate subscription scope and select the lab's date range.
2. Group/filter by resource, resource group and service. Include:

   | Resource | Baseline / added cost |
   |---|---|
   | Inference cluster | D4s_v5 system + D8s_v5 CPU model node |
   | Agents cluster | D4s_v5 system + D4s_v5 Kata node |
   | Plant cluster | D2s_v5, including while its CNI is unfinished |
   | Edge VM | D4s_v5, disk and public IP |
   | Supporting infrastructure | AKS tier, disks, load balancers, IPs, ACR, log ingestion/retention and traffic |
   | Optional exercises | GPU replicas/system nodes, separate GPU group/managed groups, v2 pools, Sandbox capacity, Grid and Content Safety dependencies |

3. Include **AKS-managed node groups** and any separate Malaysia West GPU tier. Filtering only to the base lab group can miss charges.
4. Compare AI Manager's estimate as VM cost per replica, not a full bill or a Spot quote. Cross-region traffic and idle resources can add cost.
5. Review budget alerts. They notify; they do **not** cap spend. Cost data can arrive later than resource creation.

## 5. Pause only if retaining the lab

1. Confirm ownership and target names. Do not stop shared resources.
2. For supported base AKS clusters, use the portal's **Stop** control and inspect the completed power state.
3. On the edge VM select **Stop** and verify **Stopped (deallocated)**; a guest shutdown is insufficient.
4. Review AI Manager's own supported lifecycle separately. Do not assume stopping the base clusters stops GPU compute in another group or safely manages a manager-owned cluster.
5. Disks, IPs, ACR, retained logs and other resources can still charge. For a finished GPU test, removing the disposable deployment/resources may be more appropriate than leaving them idle.
6. After restarting retained resources, recheck node readiness, Flex reconnection, model health and Guided/Inspect. Do not promise automatic recovery.

## Troubleshooting and carry forward

| Observation | Interpretation / next check |
|---|---|
| Browser works but no app telemetry | Instrumentation/configuration/sampling/export and approved egress; not necessarily an app failure. |
| No GenAI spans | Expected with the shipped dependencies; do not claim they are present. |
| Plant Insights empty | No Container insights addon is configured there. |
| Grid flow view empty | Enrollment, diagnostic category/workspace, matching time and ingestion delay. |
| GPU charges continue after base pause | Inspect separate manager-owned compute and all related groups. |

**Carry forward:** baseline/comparison outcomes, telemetry gaps, policy evidence and full resource inventory. [Module 08](08-cleanup.md) removes dependencies and confirms deletion; stopping is not cleanup.
