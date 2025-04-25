param location string
param entraConnectorName string = 'CTI-EntraID-Connector'
param managedIdentityId string
param logAnalyticsConnectionId string
param logAnalyticsQueryConnectionId string
param microsoftGraphConnectionId string
param ctiWorkspaceName string
param diagnosticSettingsRetentionDays int
param ctiWorkspaceId string
param graphApiUrl string
param tags object

resource entraIDConnectorLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: entraConnectorName
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
        graphApiUrl: {
          defaultValue: graphApiUrl
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
        Get_High_Risk_Users: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'microsoftgraph\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v1.0/identityProtection/riskyUsers'
            queries: {
              '$filter': 'riskLevel eq \'high\''
              '$select': 'id,userPrincipalName,riskLevel,riskState,riskDetail,riskLastUpdatedDateTime'
            }
          }
        }
        // Additional actions for processing risky users would be here
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

resource entraIDConnectorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: entraIDConnectorLogicApp
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

output entraConnectorResourceId string = entraIDConnectorLogicApp.id
output entraConnectorName string = entraIDConnectorLogicApp.name
