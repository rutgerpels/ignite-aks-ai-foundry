param principalId string
param acrName string
param kubeletPrincipalIds array
param clusterPrincipalIds array
param foundryAccountName string

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var azureAiUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
var aksClusterAdminRoleId = '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: 'vnet-cloud'
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for id in kubeletPrincipalIds: {
  scope: acr
  name: guid(acr.id, id, acrPullRoleId)
  properties: {
    principalId: id
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
  }
}]

// Lets each cluster identity manage internal load balancers in the BYO virtual network.
resource vnetContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for id in clusterPrincipalIds: {
  scope: vnet
  name: guid(vnet.id, id, networkContributorRoleId)
  properties: {
    principalId: id
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
  }
}]

resource userFoundry 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  scope: foundry
  name: guid(foundry.id, principalId, azureAiUserRoleId)
  properties: {
    principalId: principalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiUserRoleId)
  }
}

resource userAksAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(resourceGroup().id, principalId, aksClusterAdminRoleId)
  properties: {
    principalId: principalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', aksClusterAdminRoleId)
  }
}
