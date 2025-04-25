param location string
param threatFeedSyncName string = 'CTI-ThreatFeedSync'
param managedIdentityId string
param logAnalyticsConnectionId string
param logAnalyticsQueryConnectionId string
param ctiWorkspaceName string
param diagnosticSettingsRetentionDays int
param ctiWorkspaceId string
param tags object

resource threatFeedSyncLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: threatFeedSyncName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        workspaceName: {
          defaultValue: ctiWorkspaceName
          type: 'String'
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: 'Day'
            interval: 1
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_Feed_List: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            body: 'CTI_IntelligenceFeeds_CL\n| where FeedType_s == "CSV" and Active_b == true\n| project FeedId_g, FeedName_s, FeedURL_s, ConfigData_s, FeedType_s, ContentMapping_s'
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuremonitorlogs\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/queryData'
            queries: {
              resourcegroups: '@resourceGroup().name'
              resourcename: '@{parameters(\'workspaceName\')}'
              resourcetype: 'Log Analytics Workspace'
              subscriptions: '@{subscription().subscriptionId}'
              timerange: 'Last 7 days'
            }
          }
        }
        // Additional actions for processing feeds would be here
      }
    }
    parameters: {
      '$connections': {
        value: {
          azureloganalyticsdatacollector: {
            connectionId: logAnalyticsConnectionId
            connectionName: 'azureloganalyticsdatacollector'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
          }
          azuremonitorlogs: {
            connectionId: logAnalyticsQueryConnectionId
            connectionName: 'azuremonitorlogs'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuremonitorlogs')
          }
        }
      }
    }
  }
}

resource threatFeedSyncLogicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: threatFeedSyncLogicApp
  name: 'diagnostics'
  properties: {
    workspaceId: ctiWorkspaceId
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
        retentionPolicy: {
          days: diagnosticSettingsRetentionDays
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: diagnosticSettingsRetentionDays
          enabled: true
        }
      }
    ]
  }
}

output threatFeedSyncResourceId string = threatFeedSyncLogicApp.id
output threatFeedSyncName string = threatFeedSyncLogicApp.name
