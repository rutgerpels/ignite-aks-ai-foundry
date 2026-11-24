param location string
param tags object
param name string
param subnetId string
param logAnalyticsId string
param kataVmSize string

resource aks 'Microsoft.ContainerService/managedClusters@2026-09-02-preview' = {
  name: name
  location: location
  tags: union(tags, { role: 'agents' })
  identity: { type: 'SystemAssigned' }
  sku: { name: 'Base', tier: 'Standard' }
  properties: {
    dnsPrefix: name
    enableRBAC: true
    oidcIssuerProfile: { enabled: true }
    securityProfile: { workloadIdentity: { enabled: true } }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: '10.245.0.0/16'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
      loadBalancerSku: 'standard'
    }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: 1
        vmSize: 'Standard_D4s_v5'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        vnetSubnetID: subnetId
        type: 'VirtualMachineScaleSets'
      }
      {
        // Pod sandboxing: every pod with runtimeClassName kata-vm-isolation runs in its own micro-VM.
        name: 'kata'
        mode: 'User'
        count: 1
        vmSize: kataVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        workloadRuntime: 'KataVmIsolation'
        vnetSubnetID: subnetId
        type: 'VirtualMachineScaleSets'
        nodeLabels: { sandbox: 'kata' }
      }
    ]
    addonProfiles: {
      omsagent: {
        enabled: true
        config: { logAnalyticsWorkspaceResourceID: logAnalyticsId }
      }
    }
  }
}

output name string = aks.name
output id string = aks.id
output kubeletPrincipalId string = aks.properties.identityProfile.kubeletidentity.objectId
output principalId string = aks.identity.principalId
