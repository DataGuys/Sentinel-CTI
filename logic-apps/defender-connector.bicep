param location string
param defenderConnectorName string = 'CTI-DefenderXDR-Connector'
param managedIdentityId string
param logAnalyticsConnectionId string
param logAnalyticsQueryConnectionId string
param ctiWorkspaceName string
param diagnosticSettingsRetentionDays int
param ctiWorkspaceId string
param keyVaultName string
param clientSecretName string
param appClientId string
param tenantId string
param securityApiBaseUrl string
param tags object

resource defenderEndpointConnector 'Microsoft.Logic/workflows@2019-05-01' = {
  name: defenderConnectorName
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
        tenantId: {
          defaultValue: tenantId
          type: 'String'
        }
        clientId: {
          defaultValue: appClientId
          type: 'String'
        }
        workspaceName: {
          defaultValue: ctiWorkspaceName
          type: 'String'
        }
        securityApiUrl: {
          defaultValue: securityApiBaseUrl
          type: 'String'
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: 'Hour'
            interval: 1
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_Authentication_Token: {
          runAfter: {}
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${environment().authentication.loginEndpoint}${tenantId}/oauth2/token'
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded'
            }
            body: 'grant_type=client_credentials&client_id=${appClientId}&client_secret=${listSecrets(resourceId('Microsoft.KeyVault/vaults/secrets', keyVaultName, clientSecretName), '2023-02-01').value}&resource=https://api.securitycenter.windows.com/'
          }
        }
        Process_High_Confidence_IPs: {
          runAfter: {
            Get_Authentication_Token: ['Succeeded']
          }
          type: 'ApiConnection'
          inputs: {
            body: 'CTI_IPIndicators_CL \n| where ConfidenceScore_d >= 80 and TimeGenerated > ago(1h) and isnotempty(IPAddress_s) \n| where not(IPAddress_s matches regex "^10\\\\.|^172\\\\.(1[6-9]|2[0-9]|3[0-1])\\\\.|^192\\\\.168\\\\.")\n| where "Microsoft Defender XDR" in (split(DistributionTargets_s, ", "))\n| project IPAddress_s, ConfidenceScore_d, ThreatType_s, Description_s, IndicatorId_g, Action_s\n| limit 500'
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
              timerange: 'Last hour'
            }
          }
        }
        // Additional actions for processing file hashes and URLs would be here
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

resource defenderEndpointConnectorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: defenderEndpointConnector
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

output defenderConnectorResourceId string = defenderEndpointConnector.id
output defenderConnectorName string = defenderEndpointConnector.name
