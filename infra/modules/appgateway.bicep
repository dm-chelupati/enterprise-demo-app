@description('Azure region')
param location string

@description('Unique suffix')
param uniqueSuffix string

@description('VNet ID for the App Gateway subnet')
param vnetName string

@description('Subnet address prefix for App Gateway')
param subnetAddressPrefix string = '10.4.0.0/24'

@description('Backend target - internal storefront service IP or FQDN')
param backendTarget string

@description('Backend port')
param backendPort int = 3000

var appGwName = 'appgw-${uniqueSuffix}'
var publicIpName = 'pip-appgw-${uniqueSuffix}'
var subnetName = 'appgw-subnet'

// App Gateway needs its own subnet
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: vnetName
}

resource appGwSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: publicIpName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource appGw 'Microsoft.Network/applicationGateways@2024-01-01' = {
  name: appGwName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'gatewayIp'
        properties: {
          subnet: { id: appGwSubnet.id }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'frontendIp'
        properties: {
          publicIPAddress: { id: publicIp.id }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port80'
        properties: { port: 80 }
      }
    ]
    backendAddressPools: [
      {
        name: 'storefrontBackend'
        properties: {
          backendAddresses: [
            { ipAddress: backendTarget }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'httpSettings'
        properties: {
          port: backendPort
          protocol: 'Http'
          requestTimeout: 30
          probe: { id: resourceId('Microsoft.Network/applicationGateways/probes', appGwName, 'healthProbe') }
        }
      }
    ]
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'frontendIp') }
          frontendPort: { id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port80') }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'routingRule'
        properties: {
          priority: 100
          ruleType: 'Basic'
          httpListener: { id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'httpListener') }
          backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, 'storefrontBackend') }
          backendHttpSettings: { id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'httpSettings') }
        }
      }
    ]
    probes: [
      {
        name: 'healthProbe'
        properties: {
          protocol: 'Http'
          host: backendTarget
          path: '/api/health'
          interval: 15
          timeout: 10
          unhealthyThreshold: 3
        }
      }
    ]
  }
}

output appGwPublicIp string = publicIp.properties.ipAddress
output appGwName string = appGw.name
