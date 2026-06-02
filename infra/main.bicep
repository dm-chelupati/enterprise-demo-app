targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'swedencentral'

@description('Resource group name')
param resourceGroupName string = 'rg-enterprise-demo-swe'

@description('Unique suffix for globally unique resource names')
param uniqueSuffix string = take(uniqueString(subscription().subscriptionId, resourceGroupName), 13)

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module vnet 'modules/vnet.bicep' = {
  scope: rg
  name: 'vnet'
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
  }
}

module acr 'modules/acr.bicep' = {
  scope: rg
  name: 'acr'
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
  }
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
    amplsSubnetId: vnet.outputs.amplsSubnetId
    privateDnsZoneMonitorId: vnet.outputs.privateDnsZoneMonitorId
    privateDnsZoneOmsId: vnet.outputs.privateDnsZoneOmsId
    privateDnsZoneOdsId: vnet.outputs.privateDnsZoneOdsId
    privateDnsZoneAgentsvcId: vnet.outputs.privateDnsZoneAgentsvcId
  }
}

module postgresql 'modules/postgresql.bicep' = {
  scope: rg
  name: 'postgresql'
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
    subnetId: vnet.outputs.dbSubnetId
    privateDnsZoneId: vnet.outputs.privateDnsZonePgId
  }
}

module aks 'modules/aks.bicep' = {
  scope: rg
  name: 'aks'
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
    subnetId: vnet.outputs.aksSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    acrId: acr.outputs.acrId
  }
}

module identity 'modules/identity.bicep' = {
  scope: rg
  name: 'identity'
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
    aksClusterName: aks.outputs.clusterName
    appInsightsName: monitoring.outputs.appInsightsName
  }
}

output RESOURCE_GROUP string = rg.name
output AKS_CLUSTER_NAME string = aks.outputs.clusterName
output ACR_NAME string = acr.outputs.acrName
output ACR_LOGIN_SERVER string = acr.outputs.acrLoginServer
output PG_SERVER_NAME string = postgresql.outputs.serverName
output PG_FQDN string = postgresql.outputs.fqdn
output LAW_ID string = monitoring.outputs.logAnalyticsWorkspaceId
output LAW_NAME string = monitoring.outputs.logAnalyticsWorkspaceName
output LAW_WORKSPACE_ID string = monitoring.outputs.logAnalyticsWorkspaceCustomerId
output AI_ID string = monitoring.outputs.appInsightsId
output AI_APP_ID string = monitoring.outputs.appInsightsAppId
output AI_CONNECTION_STRING string = monitoring.outputs.appInsightsConnectionString
output AMPLS_NAME string = monitoring.outputs.amplsName
output VNET_NAME string = vnet.outputs.vnetName
