param location string
param tags object
param name string
param subnetId string

// Mirrors "Prepare an AKS cluster for flex nodes": one managed system node, no built-in
// network plugin (Unbounded-Net is installed by you during the flex node lab), no SSH.
// The system node stays NotReady until Unbounded-Net is installed - that's expected.
resource aks 'Microsoft.ContainerService/managedClusters@2026-09-02-preview' = {
  name: name
  location: location
  tags: union(tags, { role: 'plant-flex' })
  identity: { type: 'SystemAssigned' }
  properties: {
    dnsPrefix: name
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'none'
      podCidr: '10.100.0.0/16'
      serviceCidr: '10.110.0.0/16'
      dnsServiceIP: '10.110.0.10'
      loadBalancerSku: 'standard'
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        mode: 'System'
        count: 1
        vmSize: 'Standard_D2s_v5'
        osType: 'Linux'
        vnetSubnetID: subnetId
        type: 'VirtualMachineScaleSets'
        securityProfile: { sshAccess: 'Disabled' }
      }
    ]
  }
}

output name string = aks.name
output id string = aks.id
output principalId string = aks.identity.principalId
