#!/bin/sh
# Prepares azd environment values used by infra/main.parameters.json.
set -e
KEY="$HOME/.ssh/ignite_lab"
[ -f "$KEY.pub" ] || ssh-keygen -t ed25519 -f "$KEY" -N '' -q -C ignite-lab
azd env set SSH_PUBLIC_KEY "$(cat "$KEY.pub")" >/dev/null
[ -n "$(azd env get-value AZURE_PRINCIPAL_ID 2>/dev/null)" ] || azd env set AZURE_PRINCIPAL_ID "$(az ad signed-in-user show --query id -o tsv)" >/dev/null
if [ -z "$(azd env get-value ALLOWED_SSH_SOURCE 2>/dev/null)" ]; then
  IP="$(curl -s --max-time 10 https://api.ipify.org || true)"
  [ -n "$IP" ] && azd env set ALLOWED_SSH_SOURCE "$IP/32" >/dev/null
fi
for f in AIManagerPreview AKSFlexNodePreview PutMachinePreview KataVMIsolationPreview KataVMIsolationV2Preview AgentSandboxPreview; do
  s="$(az feature show --namespace Microsoft.ContainerService --name $f --query properties.state -o tsv 2>/dev/null || true)"
  [ "$s" = "Registered" ] || echo "WARNING: feature $f is '$s'. Complete module 01 in docs/code/ or docs/portal/ first."
done
