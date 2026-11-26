# 06 - Agent Grid: governed agent traffic

**Session ref:** ~24:00-30:00, policy and security across agents and tools.

[Previous: compute isolation](05-pod-sandboxing-agent-sandbox.md) | [Code experience](README.md) | [Next: evidence and cost](07-observability-cost.md)

**Learn:** compute isolation does not authorize tool calls. Keep the existing L3/L4 NetworkPolicy, then compare it with workload-identity and MCP-tool policies enforced outside the agent.

**Before:** module 01's working app and approved access to the [Agent Grid limited preview](https://learn.microsoft.com/azure/agent-grid/overview). Read the [configuration guide](https://learn.microsoft.com/azure/agent-grid/configure-agent-grid) and current regional/network limitations. No SandboxClaim integration or GPU deployment is required.

**Eligibility gate:** Grid requires its own `Microsoft.NetworkSecurity` provider, `AgentGridPreview` feature, and AKS `Microsoft.ContainerService/EnableAgentFabricPreview` registration. AKS clusters should use Entra integration; the current Bicep does not enable it. Private AKS is not supported in this preview. Resolve eligibility with the cluster owner before enrollment; this guide does not migrate identities or alter governance.

## 1. Establish the baseline

Inspect `k8s/agent/network-policy.yaml`, or AKS **Kubernetes resources > Network policies**:

| Baseline rule | Meaning |
|---|---|
| MCP ingress only from `role=agent` pods in the namespace | Limits who can connect, not which tool they invoke. |
| Agent egress to DNS, MCP pods and inference subnet TCP 11434 | Supports the current CPU app, not every possible future model gateway. |
| Agent egress to public IPv4 TCP 443 | Broader than a telemetry hostname allow list; other network/governance controls may still deny traffic. |

From the **agent pod**, test and record the result:

```powershell
$k = '--kubeconfig', '.kube/agents'
kubectl @k -n caldova get networkpolicy
kubectl @k -n caldova exec deploy/caldova-agent -- python -c "import urllib.request;print(urllib.request.urlopen('https://example.com',timeout=5).status)"
kubectl @k -n caldova exec deploy/caldova-agent -- python -c "import asyncio,app;print(asyncio.run(app.call_tool('maintenance','create_work_order',{'equipment_id':'BLP-207','summary':'synthetic policy test','priority':'high'})))"
```

Run the mock write-tool test only in the isolated lab with fictional data; record both results and UTC time before adding the policy. A 200 on the external request is useful, **not guaranteed**. DNS, egress governance or an upstream firewall can block it already. An existing denial is not proof of Agent Grid. Do not change those controls to force this demonstration.

## 2. Configure in Azure portal

Agent Grid is **not command-only**. This module keeps its documented portal configuration inline; there is no verified CLI-only replacement supplied by this lab:

1. In Azure portal search **AgentGrid**, choose **Create**, and create a lab Grid in the same subscription/region as the verified agents cluster. Wait for `Succeeded`.
2. Open **Grid members > Attached resources > Add**, choose **AKS cluster**, select the agents cluster and **Attach**. Wait for **Added to grid**.
3. Open **Grid members > Members**, find the intended workload in `caldova`, and **Enroll** it. If the cluster shows **Workloads not read**, enter `caldova` in **Namespace to read** under **Add workloads** on Attached resources. Confirm **Enrolled** and SPIFFE identity. Attachment alone does not intercept traffic.
4. Open **Policies > Add policy**, select **Create new group**, choose a lab-specific name and priority, and select the intended member under **Source > Member identities**. Choose the policy type and settings for the following rules. Review priority/order and **Member connectivity**. First applicable policy decision wins.
5. Plan allowed paths for DNS, model, MCP and actual telemetry destinations. Applicable FQDN/URL/MCP policies can deny other traffic unless allowed by policy. Do not treat example App Insights wildcards as a complete allow list.
6. Add an MCP deny rule for **`create_work_order`** while allowing the read tools needed by Guided/Autonomous. Grid rules use actual MCP tool names, not an invented `server/tool` permission syntax.
7. Open **Monitoring > Diagnostic settings > Add diagnostic setting**, select **AgentFabricFlowLogs**, send to the lab Log Analytics workspace and save.

For BYO networking, the docs require inbound TCP **15008/15009 to the Grid gateway load balancer IP** in the subnet NSG. This is not a rule with the LB IP as the source. Have the network/governance owner review effective controls; this repo defining no custom AKS-subnet NSG does not mean governance has attached none.

If using AgentGateway for AKS, the configuration guide separately requires Gateway API support. TLS inspection uses an Azure-managed CA and must be planned with the appropriate trust/security requirements. Content inspection needs your own Azure AI Content Safety connection/key and adds cost. Current Prompt Shields documentation describes JSON **request-body** inspection for POST/PUT/PATCH; do not promise arbitrary tool-response screening.

## 3. Verify enforcement against the mock tools

The app's Autonomous implementation explicitly excludes `create_work_order` (and camera capture) from its model tool list. It will **not** spontaneously exercise this deny rule. The mock maintenance server returns a synthetic `pending-approval` order; it does not implement a real approval workflow or dispatch technicians.

1. On the isolated lab only, repeat section 1's direct mock tool call **after** the deny policy. This tests defense against code that attempts an unauthorized tool, not a feature exposed by the UI:

   ```powershell
   kubectl @k -n caldova exec deploy/caldova-agent -- python -c "import asyncio,app;print(asyncio.run(app.call_tool('maintenance','create_work_order',{'equipment_id':'BLP-207','summary':'synthetic policy test','priority':'high'})))"
   ```

2. Run Guided/Autonomous in the browser: permitted read tools and model access should still work.
3. Repeat the `example.com` request if it was initially allowed and your reviewed Grid policy intentionally denies it.
4. Open **Live inspect** and **Flow map**. Correlate source member, destination, MCP method/tool, timestamp, verdict and deciding rule. Allow a few minutes for logs.

**Expected:** allowed read/inference traffic still succeeds; the deliberate write-tool request is denied by the intended Grid rule with matching flow-log evidence. A timeout alone, a failed UI run, or a NetworkPolicy/NSG denial is not evidence that the MCP policy worked. HTTP denies can return 403; the MCP client may surface this as a tool/client error rather than a raw status.

## Troubleshooting, limits and recovery

| Symptom | Check |
|---|---|
| Cannot attach | Approved preview, cluster compatibility, same region/subscription, not attached to another Grid. |
| No filtering | Enrollment, exact member identity, applied policy group, matching rule/order. |
| Everything stops | Default-deny implications, all app dependencies, existing NetworkPolicy and effective network paths. Have the owner review the lab-specific policy; don't remove shared governance. |
| No flow evidence | Diagnostic category/destination, ingestion delay, correct member and time window. |
| Content policy cannot be added | Content Safety connection and current inspection prerequisites; skip if not approved. |

Do not delete the baseline NetworkPolicy after enabling Grid or assume a deny rule supplies a human-approval workflow. Do not modify the mock manual and claim Prompt Shields detected tool-response injection without a supported, measured request-inspection path.

**Carry forward:** the allowed/denied evidence for [module 07](07-observability-cost.md). To undo only this experiment, coordinate removal of its lab-specific policies and unenrollment/detachment with the owner; do not change unrelated controls. Unenroll/detach before cluster deletion, then delete unused Grid and independent policy-group resources in [module 08](08-cleanup.md).
