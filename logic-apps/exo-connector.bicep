param location string
param exoConnectorName string = 'CTI-ExchangeOnline-Connector'
param managedIdentityId string
param logAnalyticsConnectionId string
param logAnalyticsQueryConnectionId string
param microsoftGraphConnectionId string
param ctiWorkspaceName string
param diagnosticSettingsRetentionDays int
param ctiWorkspaceId string
param tags object

resource exoConnectorLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: exoConnectorName
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
            frequency: 'Hour'
            interval: 12
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_High_Confidence_Indicators: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            body: 'CTI_ThreatIntelIndicator_CL \n| where Confidence_d >= 85 and Active_b == true\n| where TimeGenerated > ago(1d)\n| where "Exchange Online" in (split(DistributionTargets_s, ", "))\n| where Type_s in ("domain-name", "url", "email-addr", "ipv4-addr")\n| project Type_s, Value_s, Confidence_d, ThreatType_s, Description_s, Action_s, IndicatorId_g\n| limit 500'
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
              timerange: 'Last day'
            }
          }
        }
        // Additional actions for processing indicators would be here
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
          microsoftgraph: {
            connectionId: microsoftGraphConnectionId
            connectionName: 'microsoftgraph'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'microsoftgraph')
          }
        }
      }
    }
  }
}

resource exoConnectorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: exoConnectorLogicApp
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

output exoConnectorResourceId string = exoConnectorLogicApp.id
output exoConnectorName string = exoConnectorLogicApp.name
