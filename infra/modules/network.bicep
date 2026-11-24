param location string
param tags object
param allowedSshSource string

// "Cloud" network: hosts the three AKS clusters.
resource cloudVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-cloud'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ '10.10.0.0/16' ] }
    subnets: [
      { name: 'snet-aks-inference', properties: { addressPrefix: '10.10.0.0/22' } }
      { name: 'snet-aks-agents', properties: { addressPrefix: '10.10.4.0/22' } }
      { name: 'snet-aks-plant', properties: { addressPrefix: '10.10.8.0/24' } }
    ]
  }
}

resource edgeNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-plant2-edge'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-ssh-from-operator'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedSshSource
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// "Plant 2" network: simulates an on-prem / edge site, connected to the cloud
// network over layer 3 (peering stands in for VPN / ExpressRoute).
resource plantVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-plant2'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ '10.20.0.0/16' ] }
    subnets: [
      {
        name: 'snet-edge'
        properties: {
          addressPrefix: '10.20.1.0/24'
          networkSecurityGroup: { id: edgeNsg.id }
        }
      }
    ]
  }
}

resource cloudToPlant 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: cloudVnet
  name: 'cloud-to-plant2'
  properties: {
    remoteVirtualNetwork: { id: plantVnet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

resource plantToCloud 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: plantVnet
  name: 'plant2-to-cloud'
  properties: {
    remoteVirtualNetwork: { id: cloudVnet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

output inferenceSubnetId string = '${cloudVnet.id}/subnets/snet-aks-inference'
output agentsSubnetId string = '${cloudVnet.id}/subnets/snet-aks-agents'
output plantAksSubnetId string = '${cloudVnet.id}/subnets/snet-aks-plant'
output edgeSubnetId string = '${plantVnet.id}/subnets/snet-edge'
