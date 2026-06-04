targetScope = 'subscription'

@description('Azure region for all resources')
param location string

@description('Resource group name')
param resourceGroupName string

@description('Unique suffix for globally unique resource names')
param uniqueSuffix string = take(uniqueString(subscription().subscriptionId, resourceGroupName), 13)

@description('GitHub App Client ID for BYO App auth (leave empty to skip Key Vault)')
param githubAppClientId string = ''

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

module keyvault 'modules/keyvault.bicep' = if (githubAppClientId != '') {
  scope: rg
  name: 'keyvault'
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
    sreAgentPrincipalId: identity.outputs.sreAgentIdentityPrincipalId
  }
}

// Register app workload identity as PG Entra admin (for password-less DB access)
module pgAdminAppIdentity 'modules/pg-admin.bicep' = {
  scope: rg
  name: 'pgAdminAppIdentity'
  params: {
    pgServerName: postgresql.outputs.serverName
    principalId: identity.outputs.appIdentityPrincipalId
    principalName: identity.outputs.appIdentityName
    principalType: 'ServicePrincipal'
  }
}

output RESOURCE_GROUP string = rg.name
output AKS_CLUSTER_NAME string = aks.outputs.clusterName
output AKS_OIDC_ISSUER string = aks.outputs.oidcIssuerUrl
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
output KV_NAME string = githubAppClientId != '' ? keyvault.outputs.keyVaultName : ''
output KV_URI string = githubAppClientId != '' ? keyvault.outputs.keyVaultUri : ''
