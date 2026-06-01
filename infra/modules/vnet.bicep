@description('Azure region')
param location string

@description('Unique suffix for resource names')
param uniqueSuffix string

var vnetName = 'vnet-enterprise-${uniqueSuffix}'
var nsgName = 'nsg-aks-${uniqueSuffix}'

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-all-outbound'
        properties: {
          priority: 1000
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/8']
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.0.0.0/16'
          networkSecurityGroup: { id: nsg.id }
          serviceEndpoints: [
            { service: 'Microsoft.Storage' }
          ]
        }
      }
      {
        name: 'db-subnet'
        properties: {
          addressPrefix: '10.1.0.0/24'
          delegations: [
            {
              name: 'postgres-delegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
      {
        name: 'ampls-subnet'
        properties: {
          addressPrefix: '10.2.0.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource privateDnsZonePg 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${uniqueSuffix}.private.postgres.database.azure.com'
  location: 'global'
}

resource privateDnsVnetLinkPg 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZonePg
  name: 'vnet-link-pg'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

// Private DNS zones for AMPLS (monitor + oms + ods + agentsvc)
resource privateDnsZoneMonitor 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.monitor.azure.com'
  location: 'global'
}

resource privateDnsZoneOms 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.oms.opinsights.azure.com'
  location: 'global'
}

resource privateDnsZoneOds 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.ods.opinsights.azure.com'
  location: 'global'
}

resource privateDnsZoneAgentsvc 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.agentsvc.azure-automation.net'
  location: 'global'
}

// Link all AMPLS DNS zones to the VNet
resource linkMonitor 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZoneMonitor
  name: 'vnet-link-monitor'
  location: 'global'
  properties: { virtualNetwork: { id: vnet.id }; registrationEnabled: false }
}

resource linkOms 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZoneOms
  name: 'vnet-link-oms'
  location: 'global'
  properties: { virtualNetwork: { id: vnet.id }; registrationEnabled: false }
}

resource linkOds 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZoneOds
  name: 'vnet-link-ods'
  location: 'global'
  properties: { virtualNetwork: { id: vnet.id }; registrationEnabled: false }
}

resource linkAgentsvc 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZoneAgentsvc
  name: 'vnet-link-agentsvc'
  location: 'global'
  properties: { virtualNetwork: { id: vnet.id }; registrationEnabled: false }
}

output vnetName string = vnet.name
output vnetId string = vnet.id
output aksSubnetId string = vnet.properties.subnets[0].id
output dbSubnetId string = vnet.properties.subnets[1].id
output amplsSubnetId string = vnet.properties.subnets[2].id
output nsgName string = nsg.name
output privateDnsZonePgId string = privateDnsZonePg.id
output privateDnsZoneMonitorId string = privateDnsZoneMonitor.id
output privateDnsZoneOmsId string = privateDnsZoneOms.id
output privateDnsZoneOdsId string = privateDnsZoneOds.id
output privateDnsZoneAgentsvcId string = privateDnsZoneAgentsvc.id
