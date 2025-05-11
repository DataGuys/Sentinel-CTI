param location string
param mdtiConnectorName string = 'CTI-MDTI-Connector'
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
param enableMDTI bool = true
param tags object = {}

resource mdtiConnectorLogicApp 'Microsoft.Logic/workflows@2019-05-01' = if (enableMDTI) {
  name: mdtiConnectorName
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
        tenantId: {
          defaultValue: tenantId
          type: 'String'
        }
        clientId: {
          defaultValue: appClientId
          type: 'String'
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: 'Hour'
            interval: 6
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
            body: 'grant_type=client_credentials&client_id=${appClientId}&client_secret=${listSecrets(resourceId('Microsoft.KeyVault/vaults/secrets', keyVaultName, clientSecretName), '2023-02-01').value}&resource=https://api.securitycenter.microsoft.com/'
          }
        }
        Get_MDTI_Indicators: {
          runAfter: {
            Get_Authentication_Token: ['Succeeded']
          }
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://api.securitycenter.microsoft.com/api/indicators?$filter=sourceseverity eq \'High\' and expirationDateTime gt @{utcNow()}'
            headers: {
              Authorization: 'Bearer @{body(\'Get_Authentication_Token\').access_token}'
              'Content-Type': 'application/json'
            }
          }
        }
        Parse_JSON_Response: {
          runAfter: {
            Get_MDTI_Indicators: ['Succeeded']
          }
          type: 'ParseJson'
          inputs: {
            content: '@body(\'Get_MDTI_Indicators\')'
            schema: {
              type: 'object'
              properties: {
                value: {
                  type: 'array'
                  items: {
                    type: 'object'
                    properties: {
                      id: { type: 'string' }
                      indicatorValue: { type: 'string' }
                      indicatorType: { type: 'string' }
                      title: { type: 'string' }
                      description: { type: 'string' }
                      sourceseverity: { type: 'string' }
                      confidence: { type: 'integer' }
                      creationTimeDateTimeUtc: { type: 'string' }
                      expirationDateTime: { type: 'string' }
                      action: { type: 'string' }
                      threatType: { type: 'string' }
                      targetProduct: { type: 'string' }
                    }
                  }
                }
              }
            }
          }
        }
        Process_IP_Indicators: {
          runAfter: {
            Parse_JSON_Response: ['Succeeded']
          }
          type: 'Foreach'
          foreach: '@body(\'Parse_JSON_Response\').value'
          filter: {
            and: [
              {
                equals: [
                  '@item().indicatorType'
                  'IpAddress'
                ]
              }
            ]
          }
          actions: {
            Submit_IP_Indicator: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: '@{utcNow()},{item().indicatorValue},{item().confidence},{item().sourceseverity},{item().creationTimeDateTimeUtc},{item().expirationDateTime},{item().threatType},{item().title},{item().description},{item().action},MDTI,@{utcNow()},true,@{guid()}'
                headers: {
                  'Log-Type': 'CTI_IPIndicators_CL'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/api/logs'
              }
            }
          }
        }
        Process_Domain_Indicators: {
          runAfter: {
            Process_IP_Indicators: ['Succeeded']
          }
          type: 'Foreach'
          foreach: '@body(\'Parse_JSON_Response\').value'
          filter: {
            and: [
              {
                equals: [
                  '@item().indicatorType'
                  'DomainName'
                ]
              }
            ]
          }
          actions: {
            Submit_Domain_Indicator: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: '@{utcNow()},{item().indicatorValue},{item().confidence},{item().sourceseverity},{item().creationTimeDateTimeUtc},{item().expirationDateTime},{item().threatType},{item().title},{item().description},{item().action},MDTI,@{utcNow()},true,@{guid()}'
                headers: {
                  'Log-Type': 'CTI_DomainIndicators_CL'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/api/logs'
              }
            }
          }
        }
        Process_URL_Indicators: {
          runAfter: {
            Process_Domain_Indicators: ['Succeeded']
          }
          type: 'Foreach'
          foreach: '@body(\'Parse_JSON_Response\').value'
          filter: {
            and: [
              {
                equals: [
                  '@item().indicatorType'
                  'Url'
                ]
              }
            ]
          }
          actions: {
            Submit_URL_Indicator: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: '@{utcNow()},{item().indicatorValue},{item().confidence},{item().sourceseverity},{item().creationTimeDateTimeUtc},{item().expirationDateTime},{item().threatType},{item().title},{item().description},{item().action},MDTI,@{utcNow()},true,@{guid()}'
                headers: {
                  'Log-Type': 'CTI_URLIndicators_CL'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/api/logs'
              }
            }
          }
        }
        Process_FileHash_Indicators: {
          runAfter: {
            Process_URL_Indicators: ['Succeeded']
          }
          type: 'Foreach'
          foreach: '@body(\'Parse_JSON_Response\').value'
          filter: {
            and: [
              {
                or: [
                  {
                    equals: [
                      '@item().indicatorType'
                      'FileSha256'
                    ]
                  }, {
                    equals: [
                      '@item().indicatorType'
                      'FileSha1'
                    ]
                  }, {
                    equals: [
                      '@item().indicatorType'
                      'FileMd5'
                    ]
                  }
                ]
              }
            ]
          }
          actions: {
            Submit_FileHash_Indicator: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: '@{utcNow()},{item().indicatorValue},{if(equals(item().indicatorType, \'FileSha256\'), item().indicatorValue, \'\')},{if(equals(item().indicatorType, \'FileSha1\'), item().indicatorValue, \'\')},{if(equals(item().indicatorType, \'FileMd5\'), item().indicatorValue, \'\')},{item().confidence},{item().sourceseverity},{item().creationTimeDateTimeUtc},{item().expirationDateTime},{item().threatType},{item().title},{item().description},{item().action},MDTI,@{utcNow()},true,@{guid()}'
                headers: {
                  'Log-Type': 'CTI_FileHashIndicators_CL'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/api/logs'
              }
            }
          }
        }
        Update_Last_Run_Time: {
          runAfter: {
            Process_FileHash_Indicators: ['Succeeded']
          }
          type: 'ApiConnection'
          inputs: {
            body: 'CTI_Metadata_CL | where Source_s == "MDTI" | extend LastRunTime_t = datetime("@{utcNow()}")'
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/api/logs'
          }
        }
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

resource mdtiConnectorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMDTI) {
  scope: mdtiConnectorLogicApp
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

output mdtiConnectorResourceId string = enableMDTI ? mdtiConnectorLogicApp.id : ''
output mdtiConnectorName string = enableMDTI ? mdtiConnectorName : ''
