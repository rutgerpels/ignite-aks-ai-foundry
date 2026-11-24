param location string
param tags object
param token string
param appInsightsId string
@secure()
param appInsightsConnectionString string

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: 'aif-caldova-${token}'
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: 'aif-caldova-${token}'
    allowProjectManagement: true
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: 'caldova-line-troubleshooting'
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    displayName: 'Caldova line troubleshooting'
    description: 'Ignite BRK420 lab - Foundry models and agents on AKS'
  }
}

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-06-01' = {
  parent: account
  name: 'appinsights'
  properties: {
    category: 'AppInsights'
    target: appInsightsId
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: { key: appInsightsConnectionString }
    metadata: { ApiType: 'Azure', ResourceId: appInsightsId }
  }
}

output accountName string = account.name
output projectName string = project.name
output endpoint string = account.properties.endpoint
