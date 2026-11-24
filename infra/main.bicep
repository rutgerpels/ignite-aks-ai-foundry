targetScope = 'subscription'

@minLength(1)
@maxLength(48)
@description('azd environment name, used to name the resource group and resources.')
param environmentName string

@description('Azure region. The session demo uses swedencentral; southcentralus is the fallback.')
param location string = 'swedencentral'

@description('SSH public key used for the edge "plant" VM (flex node host).')
param sshPublicKey string

@description('Public IP / CIDR allowed to SSH into the edge VM (your workstation).')
param allowedSshSource string = '*'

@description('Object ID of the user running the lab. Gets admin roles on clusters and Foundry.')
param principalId string = ''

@description('VM size for the CPU model node pool on the inference cluster.')
param cpuModelVmSize string = 'Standard_D8s_v5'

@description('VM size for the Kata (pod sandbox) node pool. Must support nested virtualization.')
param kataVmSize string = 'Standard_D4s_v5'

var tags = { 'azd-env-name': environmentName, workload: 'ignite-aks-ai-foundry' }
var token = toLower(uniqueString(subscription().id, environmentName, location))

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: { location: location, tags: tags, token: token }
}

module network 'modules/network.bicep' = {
  scope: rg
  name: 'network'
  params: { location: location, tags: tags, allowedSshSource: allowedSshSource }
}

module acr 'modules/acr.bicep' = {
  scope: rg
  name: 'acr'
  params: { location: location, tags: tags, token: token }
}

// Cluster 1: "inference" - eligible as a bring-your-own cluster for AKS AI Manager
// (Azure CNI overlay + Cilium dataplane, system-assigned MI, Kubernetes RBAC).
module aksInference 'modules/aks-inference.bicep' = {
  scope: rg
  name: 'aks-inference'
  params: {
    location: location
    tags: tags
    name: 'aks-inference-${token}'
    subnetId: network.outputs.inferenceSubnetId
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    cpuModelVmSize: cpuModelVmSize
  }
}

// Cluster 2: "agents" - hosts agents and MCP servers in Kata micro-VM pod sandboxes.
module aksAgents 'modules/aks-agents.bicep' = {
  scope: rg
  name: 'aks-agents'
  params: {
    location: location
    tags: tags
    name: 'aks-agents-${token}'
    subnetId: network.outputs.agentsSubnetId
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    kataVmSize: kataVmSize
  }
}

// Cluster 3: "plant" - minimal cluster without a built-in CNI, used for the flex node join walkthrough.
module aksPlant 'modules/aks-plant.bicep' = {
  scope: rg
  name: 'aks-plant'
  params: {
    location: location
    tags: tags
    name: 'aks-plant-${token}'
    subnetId: network.outputs.plantAksSubnetId
  }
}

module edgeVm 'modules/edge-vm.bicep' = {
  scope: rg
  name: 'edge-vm'
  params: {
    location: location
    tags: tags
    name: 'vm-plant2-edge'
    subnetId: network.outputs.edgeSubnetId
    sshPublicKey: sshPublicKey
  }
}

module foundry 'modules/foundry.bicep' = {
  scope: rg
  name: 'foundry'
  params: {
    location: location
    tags: tags
    token: token
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

module roles 'modules/roles.bicep' = {
  scope: rg
  name: 'roles'
  params: {
    principalId: principalId
    acrName: acr.outputs.name
    kubeletPrincipalIds: [
      aksInference.outputs.kubeletPrincipalId
      aksAgents.outputs.kubeletPrincipalId
    ]
    clusterPrincipalIds: [
      aksInference.outputs.principalId
      aksAgents.outputs.principalId
      aksPlant.outputs.principalId
    ]
    foundryAccountName: foundry.outputs.accountName
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AKS_INFERENCE_NAME string = aksInference.outputs.name
output AKS_INFERENCE_ID string = aksInference.outputs.id
output AKS_AGENTS_NAME string = aksAgents.outputs.name
output AKS_AGENTS_ID string = aksAgents.outputs.id
output AKS_PLANT_NAME string = aksPlant.outputs.name
output AKS_PLANT_ID string = aksPlant.outputs.id
output EDGE_VM_NAME string = edgeVm.outputs.name
output EDGE_VM_PUBLIC_IP string = edgeVm.outputs.publicIp
output EDGE_VM_PRIVATE_IP string = edgeVm.outputs.privateIp
output EDGE_VM_IDENTITY_CLIENT_ID string = edgeVm.outputs.identityClientId
output EDGE_VM_IDENTITY_ID string = edgeVm.outputs.identityId
output FOUNDRY_ACCOUNT_NAME string = foundry.outputs.accountName
output FOUNDRY_PROJECT_NAME string = foundry.outputs.projectName
output FOUNDRY_ENDPOINT string = foundry.outputs.endpoint
output LOG_ANALYTICS_ID string = monitoring.outputs.logAnalyticsId
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.appInsightsConnectionString
