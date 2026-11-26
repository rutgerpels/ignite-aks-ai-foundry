# Choose a lab experience

[Lab home](../README.md)

Pick one folder and follow its modules in order. Each experience contains setup, the optional exercises, verification, troubleshooting and cleanup. You do not need to read the other experience.

| Experience | Start | How it works |
|---|---|---|
| **Portal** | [Portal experience](portal/README.md) | Azure/Foundry portal and browser steps first. Necessary commands and YAML are included in the module where you need them, with the correct shell and target. |
| **Code** | [Code experience](code/README.md) | PowerShell/Bash, Bicep and Kubernetes commands first. Documented portal-only/access-gated operations are explained inline. |

Both use the same repository and baseline resources. These folders are alternative instructions, **not two deployments**. If the lab already exists, resume it rather than running setup again.

| Module | Portal experience | Code experience |
|---|---|---|
| 01 - Access, setup and CPU baseline | [Portal 01](portal/01-prerequisites.md) | [Code 01](code/01-prerequisites.md) |
| 02 - AI Manager model deployment | [Portal 02](portal/02-aks-ai-manager.md) | [Code 02](code/02-aks-ai-manager.md) |
| 03 - Foundry project and hosting boundary | [Portal 03](portal/03-foundry-aks-compute.md) | [Code 03](code/03-foundry-aks-compute.md) |
| 04 - Flex nodes and plant compute | [Portal 04](portal/04-flex-nodes.md) | [Code 04](code/04-flex-nodes.md) |
| 05 - Kata isolation and Agent Sandbox | [Portal 05](portal/05-pod-sandboxing-agent-sandbox.md) | [Code 05](code/05-pod-sandboxing-agent-sandbox.md) |
| 06 - Agent Grid | [Portal 06](portal/06-agent-grid.md) | [Code 06](code/06-agent-grid.md) |
| 07 - Observability and cost | [Portal 07](portal/07-observability-cost.md) | [Code 07](code/07-observability-cost.md) |
| 08 - Cleanup | [Portal 08](portal/08-cleanup.md) | [Code 08](code/08-cleanup.md) |
