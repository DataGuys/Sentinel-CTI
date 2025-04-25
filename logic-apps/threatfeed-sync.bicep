param location string
param syncConnectorName string = 'CTI-ThreatIntelSync-Connector'
param managedIdentityId string
param logAnalyticsConnectionId string
param logAnalyticsQueryConnectionId string
param ctiWorkspaceName string
param diagnosticSettingsRetentionDays int
param ctiWorkspaceId string
param tags object

resource threatIntelSyncLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: syncConnectorName
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
            frequency: 'Minute'
            interval: 15
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_New_Indicators: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            body: 'CTI_ThreatIntelIndicator_CL\n| where TimeGenerated > ago(30m)\n| extend IndicatorType = Type_s\n| where isnotempty(Value_s)\n| project TimeGenerated, IndicatorId_g, IndicatorType, Value_s, Pattern_s, ThreatType_s, Description_s, Action_s, Confidence_d, ValidFrom_t, ValidUntil_t, TLP_s, DistributionTargets_s, Source_s, Active_b, AdditionalFields'
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
              timerange: 'Last 30 minutes'
            }
          }
        },
        Process_IP_Indicators: {
          runAfter: {
            Get_New_Indicators: ['Succeeded']
          }
          type: 'Foreach'
          foreach: '@body(\'Get_New_Indicators\').tables[0].rows'
          filter: {
            and: [
              {
                equals: [
                  '@item()[2]',
                  'ip-addr'
                ]
              }
            ]
          }
          actions: {
            Submit_IP_Indicator: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: '@{utcNow()},{item()[3]},{item()[9]},{item()[13]},{item()[10]},{item()[11]},{item()[8]},{item()[5]},{item()[14]},{item()[7]},{item()[12]},@{utcNow()},@{item()[14]},@{item()[0]},@{guid()}'
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
        },
        Process_Domain_Indicators: {
          runAfter: {
            Process_IP_Indicators: ['Succeeded']
          }
          type: 'Foreach'
          foreach: '@body(\'Get_New_Indicators\').tables[0].rows'
          filter: {
            and: [
              {
                equals: [
                  '@item()[2]',
                  'domain-name'
                ]
              }
            ]
          }
          actions: {
            Submit_Domain_Indicator: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: '@{utcNow()},{item()[3]},{item()[9]},{item()[13]},{item()[10]},{item()[11]},{item()[8]},{item()[5]},{item()[14]},{item()[7]},{item()[12]},@{utcNow()},@{item()[14]},@{item()[0]},@{guid()}'
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
        },
        Process_URL_Indicators: {
          runAfter: {
            Process_Domain_Indicators: ['Succeeded']
          }
          type: 'Foreach'
          foreach: '@body(\'Get_New_Indicators\').tables[0].rows'
          filter: {
            and: [
              {
                equals: [
                  '@item()[2]',
                  'url'
                ]
              }
            ]
          }
          actions: {
            Submit_URL_Indicator: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: '@{utcNow()},{item()[3]},{item()[9]},{item()[13]},{item()[10]},{item()[11]},{item()[8]},{item()[5]},{item()[14]},{item()[7]},{item()[12]},@{utcNow()},@{item()[14]},@{item()[0]},@{guid()}'
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
        },
        Process_FileHash_Indicators: {
          runAfter: {
            Process_URL_Indicators: ['Succeeded']
          }
          type: 'Foreach'
          foreach: '@body(\'Get_New_Indicators\').tables[0].rows'
          filter: {
            and: [
              {
                or: [
                  {
                    equals: [
                      '@item()[2]',
                      'file'
                    ]
                  },
                  {
                    equals: [
                      '@item()[2]',
                      'file-sha256'
                    ]
                  },
                  {
                    equals: [
                      '@item()[2]',
                      'file-sha1'
                    ]
                  },
                  {
                    equals: [
                      '@item()[2]',
                      'file-md5'
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
                body: '@{utcNow()},{item()[3]},{if(equals(item()[2], \'file-sha256\') or contains(item()[4], \'file:hashes.\'SHA256\'), item()[3], \'\')},{if(equals(item()[2], \'file-md5\') or contains(item()[4], \'file:hashes.\'MD5\'), item()[3], \'\')},{if(equals(item()[2], \'file-sha1\') or contains(item()[4], \'file:hashes.\'SHA1\'), item()[3], \'\')},{item()[9]},{item()[13]},{item()[10]},{item()[11]},{item()[8]},{item()[5]},{item()[14]},{item()[7]},{item()[12]},@{utcNow()},@{item()[14]},@{item()[0]},@{guid()}'
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

resource threatIntelSyncLogicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: threatIntelSyncLogicApp
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

output threatIntelSyncResourceId string = threatIntelSyncLogicApp.id
output threatIntelSyncName string = threatIntelSyncLogicApp.name
