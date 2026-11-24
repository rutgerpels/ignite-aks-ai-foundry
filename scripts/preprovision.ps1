# Prepares azd environment values used by infra/main.parameters.json.
$ErrorActionPreference = 'Stop'

$keyPath = Join-Path $HOME '.ssh/ignite_lab'
if (-not (Test-Path "$keyPath.pub")) {
    Write-Host "Generating SSH key $keyPath for the edge VM..."
    $PSNativeCommandArgumentPassing = 'Standard'
    ssh-keygen -t ed25519 -f $keyPath -N '' -q -C ignite-lab
}
azd env set SSH_PUBLIC_KEY (Get-Content "$keyPath.pub" -Raw).Trim() | Out-Null

if (-not (azd env get-value AZURE_PRINCIPAL_ID 2>$null)) {
    azd env set AZURE_PRINCIPAL_ID (az ad signed-in-user show --query id -o tsv) | Out-Null
}

if (-not (azd env get-value ALLOWED_SSH_SOURCE 2>$null)) {
    try {
        $ip = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).Trim()
        azd env set ALLOWED_SSH_SOURCE "$ip/32" | Out-Null
        Write-Host "Edge VM SSH restricted to $ip/32"
    } catch { Write-Warning 'Could not detect public IP; SSH to the edge VM will be open to any source.' }
}

foreach ($f in 'AIManagerPreview', 'AKSFlexNodePreview', 'PutMachinePreview', 'KataVMIsolationPreview', 'KataVMIsolationV2Preview', 'AgentSandboxPreview') {
    $state = az feature show --namespace Microsoft.ContainerService --name $f --query properties.state -o tsv 2>$null
    if ($state -ne 'Registered') { Write-Warning "Feature $f is '$state'. Run docs/01-prerequisites.md first." }
}
