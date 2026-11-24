param location string
param tags object
param name string
param subnetId string
param sshPublicKey string
param vmSize string = 'Standard_D4s_v5'
param adminUsername string = 'azureuser'

// Host identity the flex node agent uses to authenticate to Azure (Entra) when joining AKS.
resource hostIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${name}'
  location: location
  tags: tags
}

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    // Required so the host can forward pod traffic for the flex site.
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: subnetId }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: union(tags, { role: 'plant2-edge-host' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${hostIdentity.id}': {} }
  }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: name
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            { path: '/home/${adminUsername}/.ssh/authorized_keys', keyData: sshPublicKey }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 64
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: { networkInterfaces: [ { id: nic.id } ] }
  }
}

output name string = vm.name
output publicIp string = pip.properties.ipAddress
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output identityId string = hostIdentity.id
output identityClientId string = hostIdentity.properties.clientId
output identityPrincipalId string = hostIdentity.properties.principalId
