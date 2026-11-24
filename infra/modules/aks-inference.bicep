param location string
param tags object
param name string
param subnetId string
param logAnalyticsId string
param cpuModelVmSize string

// Meets the AKS AI Manager bring-your-own-cluster requirements:
// same region, Kubernetes RBAC, system-assigned managed identity, Azure CNI + Cilium dataplane.
resource aks 'Microsoft.ContainerService/managedClusters@2026-09-02-preview' = {
  name: name
  location: location
  tags: union(tags, { role: 'inference' })
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
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
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
        // CPU stand-in for the GPU node pools used in the session (no GPU quota needed).
        name: 'cpumodels'
        mode: 'User'
        count: 1
        vmSize: cpuModelVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        osDiskSizeGB: 128
        vnetSubnetID: subnetId
        type: 'VirtualMachineScaleSets'
        nodeLabels: { workload: 'cpu-models' }
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
