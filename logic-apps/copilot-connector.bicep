param location string
param securityCopilotConnectorName string = 'CTI-SecurityCopilot-Connector'
param managedIdentityId string
param logAnalyticsConnectionId string
param logAnalyticsQueryConnectionId string
param ctiWorkspaceName string
param diagnosticSettingsRetentionDays int
param ctiWorkspaceId string
param enableSecurityCopilot bool
param dceNameForCopilot string
param tags object

resource securityCopilotConnector 'Microsoft.Logic/workflows@2019-05-01' = if (enableSecurityCopilot) {
  name: securityCopilotConnectorName
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
        Get_Intelligence: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            body: 'CTI_ThreatIntelIndicator_CL \n| where TimeGenerated > ago(7d)\n| where Active_b == true\n| where Source_s != "Microsoft Security Copilot"\n| order by Confidence_d desc\n| project Type_s, Value_s, Description_s, Source_s, ThreatType_s, Confidence_d, IndicatorId_g, ValidFrom_t\n| limit 100'
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
        // Additional actions for processing intelligence would be here
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

resource securityCopilotConnectorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableSecurityCopilot) {
  scope: securityCopilotConnector
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

// Data Collection Endpoint for Security Copilot integration
resource dce 'Microsoft.Insights/dataCollectionEndpoints@2021-09-01-preview' = if (enableSecurityCopilot) {
  name: dceNameForCopilot
  location: location
  tags: tags
  kind: 'Windows'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

output securityCopilotConnectorResourceId string = enableSecurityCopilot ? securityCopilotConnector.id : ''
output securityCopilotConnectorName string = enableSecurityCopilot ? securityCopilotConnectorName : ''
output dceResourceId string = enableSecurityCopilot ? dce.id : ''
