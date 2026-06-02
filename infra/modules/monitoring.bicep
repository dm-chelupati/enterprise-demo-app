@description('Azure region')
param location string

@description('Unique suffix')
param uniqueSuffix string

@description('Subnet ID for AMPLS private endpoint')
param amplsSubnetId string

@description('Private DNS zone IDs for AMPLS')
param privateDnsZoneMonitorId string
param privateDnsZoneOmsId string
param privateDnsZoneOdsId string
param privateDnsZoneAgentsvcId string

var lawName = 'law-${uniqueSuffix}'
var aiName = 'ai-${uniqueSuffix}'
var amplsName = 'ampls-${uniqueSuffix}'

// Log Analytics Workspace
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

// Azure Monitor Private Link Scope
resource ampls 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
  name: amplsName
  location: 'global'
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

// Link LAW to AMPLS
resource amplsLaw 'microsoft.insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: 'law-link'
  properties: {
    linkedResourceId: law.id
  }
}

// Link App Insights to AMPLS
resource amplsAi 'microsoft.insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: 'ai-link'
  properties: {
    linkedResourceId: appInsights.id
  }
}

// Private endpoint for AMPLS
resource amplsPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: 'pe-${amplsName}'
  location: location
  properties: {
    subnet: { id: amplsSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'ampls-connection'
        properties: {
          privateLinkServiceId: ampls.id
          groupIds: [ 'azuremonitor' ]
        }
      }
    ]
  }
}

// DNS zone groups for the private endpoint
resource amplsDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: amplsPrivateEndpoint
  name: 'ampls-dns'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'monitor'
        properties: { privateDnsZoneId: privateDnsZoneMonitorId }
      }
      {
        name: 'oms'
        properties: { privateDnsZoneId: privateDnsZoneOmsId }
      }
      {
        name: 'ods'
        properties: { privateDnsZoneId: privateDnsZoneOdsId }
      }
      {
        name: 'agentsvc'
        properties: { privateDnsZoneId: privateDnsZoneAgentsvcId }
      }
    ]
  }
}

// Alert rules
resource alertRule5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'app-5xx-errors-${uniqueSuffix}'
  location: 'global'
  properties: {
    description: 'App returning 5xx errors'
    severity: 2
    enabled: true
    scopes: [ appInsights.id ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'failed-requests'
          metricName: 'requests/failed'
          metricNamespace: 'microsoft.insights/components'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
  }
}

// Diagnostic settings — Activity Logs to LAW (resource group scope)
resource diagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'law-diagnostics'
  scope: law
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output logAnalyticsWorkspaceId string = law.id
output logAnalyticsWorkspaceName string = law.name
output logAnalyticsWorkspaceCustomerId string = law.properties.customerId
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsAppId string = appInsights.properties.AppId
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output amplsId string = ampls.id
output amplsName string = ampls.name
