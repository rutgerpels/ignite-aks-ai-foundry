# Builds the sample images in ACR and deploys the CPU models + Caldova sample to the clusters.
# Runs automatically as the azd postprovision hook; safe to re-run.
param([string]$Tag = 'v1', [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Get-AzdValue($name) { (azd env get-value $name).Trim() }
$rg = Get-AzdValue AZURE_RESOURCE_GROUP
$acr = Get-AzdValue AZURE_CONTAINER_REGISTRY_NAME
$acrServer = Get-AzdValue AZURE_CONTAINER_REGISTRY_ENDPOINT
$inference = Get-AzdValue AKS_INFERENCE_NAME
$agents = Get-AzdValue AKS_AGENTS_NAME
$root = Split-Path $PSScriptRoot -Parent
$kubeDir = Join-Path $root '.kube'
New-Item -ItemType Directory -Force $kubeDir | Out-Null
$kcInference = Join-Path $kubeDir 'inference'
$kcAgents = Join-Path $kubeDir 'agents'

if (-not $SkipBuild) {
    Write-Host '==> Building images in ACR (az acr build)'
    foreach ($svc in @(@('agent', 'caldova-agent'), @('mcp-plant-signals', 'caldova-mcp-plant-signals'), @('mcp-maintenance', 'caldova-mcp-maintenance'))) {
        az acr build -r $acr -t "$($svc[1]):$Tag" (Join-Path $root "src/$($svc[0])") --no-logs -o none
    }
}

Write-Host '==> Fetching cluster credentials into .kube/'
az aks get-credentials -g $rg -n $inference --admin -f $kcInference --overwrite-existing -o none
az aks get-credentials -g $rg -n $agents --admin -f $kcAgents --overwrite-existing -o none

Write-Host '==> Inference cluster: Ollama with CPU models'
kubectl --kubeconfig $kcInference apply -f (Join-Path $root 'k8s/inference/ollama.yaml')
Write-Host 'Waiting for the internal load balancer IP...'
$llmIp = ''
for ($i = 0; $i -lt 60 -and -not $llmIp; $i++) {
    $llmIp = kubectl --kubeconfig $kcInference -n models get svc ollama -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    if (-not $llmIp) { Start-Sleep 10 }
}
if (-not $llmIp) { throw 'Ollama internal load balancer did not get an IP.' }
azd env set LLM_INTERNAL_IP $llmIp | Out-Null
Write-Host "Model endpoint: http://${llmIp}:11434/v1"

Write-Host '==> Agents cluster: MCP servers + Caldova agent (Kata sandbox)'
$vars = @{ '${ACR}' = $acrServer; '${TAG}' = $Tag; '${LLM_IP}' = $llmIp; '${APPINSIGHTS_CS}' = (Get-AzdValue APPLICATIONINSIGHTS_CONNECTION_STRING) }
foreach ($f in 'mcp-servers.yaml', 'agent.yaml', 'network-policy.yaml') {
    $yaml = Get-Content (Join-Path $root "k8s/agent/$f") -Raw
    foreach ($k in $vars.Keys) { $yaml = $yaml.Replace($k, $vars[$k]) }
    $yaml | kubectl --kubeconfig $kcAgents apply -f -
}
kubectl --kubeconfig $kcAgents -n caldova rollout restart deploy/caldova-agent | Out-Null
kubectl --kubeconfig $kcAgents -n caldova rollout status deploy/caldova-agent --timeout=10m

$agentIp = ''
for ($i = 0; $i -lt 60 -and -not $agentIp; $i++) {
    $agentIp = kubectl --kubeconfig $kcAgents -n caldova get svc caldova-agent -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    if (-not $agentIp) { Start-Sleep 10 }
}
azd env set AGENT_URL "http://$agentIp" | Out-Null

Write-Host ''
Write-Host "Caldova agent UI : http://$agentIp"
Write-Host "kubeconfigs      : $kcInference , $kcAgents"
Write-Host 'Model download   : kubectl --kubeconfig .kube/inference -n models logs job/pull-models -f'
