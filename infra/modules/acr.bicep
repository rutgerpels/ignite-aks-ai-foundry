param location string
param tags object
param token string

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'acr${token}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

output name string = acr.name
output loginServer string = acr.properties.loginServer
