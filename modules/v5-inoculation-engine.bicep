// modules/v5-inoculation-engine.bicep
@description('Primary Azure region')
param location string

@description('Resource name prefix')
param prefix string = 'cti'

@description('Environment (prod, dev, test)')
param environment string = 'prod'

@description('User-assigned managed identity ID')
param managedIdentityId string

@description('Log Analytics data collector connection ID')
param logAnalyticsConnectionId string

@description('Log Analytics query connection ID')
param logAnalyticsQueryConnectionId string

@description('Log Analytics workspace name')
param ctiWorkspaceName string

@description('Log Analytics workspace ID')
param ctiWorkspaceId string

@description('Key Vault name')
param keyVaultName string

@description('Resource tags')
param tags object = {}

// Production-ready enhancements
@description('Enable telemetry for monitoring')
param enableTelemetry bool = true

@description('Enable auto-scaling for Logic Apps')
param enableAutoScaling bool = true

@description('Error retry count')
@minValue(1)
@maxValue(10)
param maxRetryCount int = 3

@description('Telemetry workspace ID (optional)')
param telemetryWorkspaceId string = ''

// The core inoculation engine - with enhanced error handling and telemetry
resource inoculationEngine 'Microsoft.Logic/workflows@2019-05-01' = {
  name: '${prefix}-InoculationEngine-${environment}'
  location: location
  tags: union(tags, {
    Component: 'Inoculation Engine'
    Version: 'V5'
  })
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
        maxRetryCount: {
          defaultValue: maxRetryCount
          type: 'Int'
        }
        telemetryEnabled: {
          defaultValue: enableTelemetry
          type: 'Bool'
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: 'Minute'
            interval: 5
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Initialize_Variables: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'allPlatforms',
                type: 'array',
                value: [
                  'Microsoft Defender XDR',
                  'Microsoft Sentinel',
                  'Exchange Online',
                  'Microsoft Security Copilot',
                  'Entra ID',
                  'AWS Security Hub',
                  'AWS Network Firewall',
                  'AWS WAF',
                  'GCP Security Command Center',
                  'GCP Cloud Armor',
                  'Palo Alto',
                  'Cisco',
                  'Fortinet',
                  'Check Point',
                  'CrowdStrike',
                  'Carbon Black',
                  'SentinelOne'
                ]
              },
              {
                name: 'processingErrors',
                type: 'array',
                value: []
              },
              {
                name: 'retryCount',
                type: 'integer',
                value: 0
              },
              {
                name: 'processingMetrics',
                type: 'object',
                value: {
                  totalProcessed: 0,
                  successCount: 0,
                  errorCount: 0,
                  tierOneCount: 0,
                  tierTwoCount: 0,
                  tierThreeCount: 0,
                  startTime: '@{utcNow()}'
                }
              }
            ]
          }
        },
        
        // V5 Enhancement: Verify environment health before proceeding
        Check_Environment_Health: {
          runAfter: {
            Initialize_Variables: [
              'Succeeded'
            ]
          },
          type: 'Http',
          inputs: {
            method: 'GET',
            uri: 'https://@{workflow().name}.azurewebsites.net/runtime/webhooks/workflow/api/management/workflows/@{workflow().name}/health',
            authentication: {
              type: 'ManagedServiceIdentity',
              identity: managedIdentityId
            }
          }
        },
        
        Verify_Health_Status: {
          runAfter: {
            Check_Environment_Health: [
              'Succeeded'
            ]
          },
          type: 'If',
          expression: {
            equals: [
              '@body(\'Check_Environment_Health\').status',
              'Healthy'
            ]
          },
          actions: {
            Get_New_Indicators: {
              runAfter: {},
              type: 'ApiConnection',
              inputs: {
                body: 'CTI_ThreatIntelIndicator_CL \n| where TimeGenerated > ago(15m) and Active_b == true and isnotempty(Value_s)\n| where isempty(EnforcementStatus_s) or EnforcementStatus_s == "Pending"\n| project TimeGenerated, Type_s, Value_s, Name_s, Description_s, Action_s, Confidence_d, \nValidFrom_t, ValidUntil_t, TLP_s, ThreatType_s, DistributionTargets_s, IndicatorId_g, \nRiskScore_d, EnforcementStatus_s',
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azuremonitorlogs\'][\'connectionId\']'
                  }
                },
                method: 'post',
                path: '/queryData',
                queries: {
                  resourcegroups: '@resourceGroup().name',
                  resourcename: '@{parameters(\'workspaceName\')}',
                  resourcetype: 'Log Analytics Workspace',
                  subscriptions: '@{subscription().subscriptionId}',
                  timerange: 'Last 15 minutes'
                }
              },
              // V5 Enhancement: Retry logic for connectivity issues
              retryPolicy: {
                type: 'fixed',
                count: '@parameters(\'maxRetryCount\')',
                interval: 'PT30S'
              }
            },
            
            Set_Processing_Count: {
              runAfter: {
                Get_New_Indicators: [
                  'Succeeded'
                ]
              },
              type: 'SetVariable',
              inputs: {
                name: 'processingMetrics',
                value: {
                  totalProcessed: '@length(body(\'Get_New_Indicators\').tables[0].rows)',
                  successCount: 0,
                  errorCount: 0,
                  tierOneCount: 0,
                  tierTwoCount: 0,
                  tierThreeCount: 0,
                  startTime: '@{variables(\'processingMetrics\').startTime}'
                }
              }
            },
            
            For_Each_Indicator: {
              foreach: '@body(\'Get_New_Indicators\').tables[0].rows',
              actions: {
                // Tier 1: High Confidence + Green/White TLP → Auto-distribute everywhere
                Process_Tier1_Indicators: {
                  type: 'If',
                  expression: {
                    and: [
                      {
                        greaterOrEquals: ['@item()[6]', 85] // Confidence >= 85
                      },
                      {
                        or: [
                          { equals: ['@item()[9]', 'TLP:GREEN'] },
                          { equals: ['@item()[9]', 'TLP:WHITE'] }
                        ]
                      }
                    ]
                  },
                  actions: {
                    Set_Enforcement_Status_Processing: {
                      runAfter: {},
                      type: 'ApiConnection',
                      inputs: {
                        body: 'let indicatorId = "@{item()[12]}";\nlet now = now();\nCTI_ThreatIntelIndicator_CL\n| where IndicatorId_g == indicatorId\n| extend EnforcementStatus_s = "Processing"\n| extend UpdatedTimeUtc_t = now',
                        host: {
                          connection: {
                            name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                          }
                        },
                        method: 'post',
                        path: '/api/logs'
                      }
                    },
                    
                    Increment_Tier_One_Count: {
                      runAfter: {
                        Set_Enforcement_Status_Processing: [
                          'Succeeded'
                        ]
                      },
                      type: 'SetVariable',
                      inputs: {
                        name: 'processingMetrics',
                        value: {
                          totalProcessed: '@{variables(\'processingMetrics\').totalProcessed}',
                          successCount: '@{variables(\'processingMetrics\').successCount}',
                          errorCount: '@{variables(\'processingMetrics\').errorCount}',
                          tierOneCount: '@{add(variables(\'processingMetrics\').tierOneCount, 1)}',
                          tierTwoCount: '@{variables(\'processingMetrics\').tierTwoCount}',
                          tierThreeCount: '@{variables(\'processingMetrics\').tierThreeCount}',
                          startTime: '@{variables(\'processingMetrics\').startTime}'
                        }
                      }
                    },
                    
                    Distribute_to_All_Targets: {
                      runAfter: {
                        Increment_Tier_One_Count: [
                          'Succeeded'
                        ]
                      },
                      type: 'ApiConnection',
                      inputs: {
                        host: {
                          connection: {
                            name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                          }
                        },
                        method: 'post',
                        body: '@{item()[0]},@{guid()},@{item()[12]},,,@{item()[1]},@{item()[2]},@{item()[11]},AutoDistribute,Success,High confidence + TLP:GREEN/WHITE = Auto-distribute,@{utcNow()}',
                        headers: {
                          'Log-Type': 'CTI_DistributionHistory_CL'
                        },
                        path: '/api/logs'
                      },
                      // V5 Enhancement: retry logic for critical operations
                      retryPolicy: {
                        type: 'fixed',
                        count: '@parameters(\'maxRetryCount\')',
                        interval: 'PT10S'
                      }
                    },
                    
                    For_Each_Target_Platform: {
                      runAfter: {
                        Distribute_to_All_Targets: [
                          'Succeeded'
                        ]
                      },
                      type: 'Foreach',
                      foreach: '@split(item()[11], \', \')',
                      actions: {
                        Try_Platform_Distribution: {
                          type: 'Try',
                          actions: {
                            Switch_Platform_Type: {
                              type: 'Switch',
                              expression: '@items(\'For_Each_Target_Platform\')',
                              cases: {
                                // Microsoft Defender XDR
                                'Microsoft Defender XDR': {
                                  actions: {
                                    Send_to_Defender_Connector: {
                                      type: 'Http',
                                      inputs: {
                                        method: 'POST',
                                        uri: 'https://${prefix}-DefenderXDR-Connector-${environment}.azurewebsites.net/api/indicator/distribute',
                                        body: {
                                          indicatorType: '@{item()[1]}',
                                          indicatorValue: '@{item()[2]}',
                                          action: '@{item()[5]}',
                                          title: '@{item()[3]}',
                                          description: '@{item()[4]}',
                                          confidenceScore: '@{item()[6]}',
                                          tlp: '@{item()[9]}',
                                          threatType: '@{item()[10]}',
                                          validFrom: '@{item()[7]}',
                                          validUntil: '@{item()[8]}',
                                          indicatorId: '@{item()[12]}'
                                        }
                                      },
                                      retryPolicy: {
                                        type: 'fixed',
                                        count: '@parameters(\'maxRetryCount\')',
                                        interval: 'PT10S'
                                      }
                                    }
                                  }
                                },
                                // Plus other platforms...
                                // AWS Security Hub, GCP Security Command Center, etc.
                              },
                              default: {
                                actions: {
                                  Log_Unsupported_Platform: {
                                    type: 'ApiConnection',
                                    inputs: {
                                      host: {
                                        connection: {
                                          name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                        }
                                      },
                                      method: 'post',
                                      body: '@{utcNow()},@{guid()},@{item()[12]},,,@{item()[1]},@{item()[2]},@{items(\'For_Each_Target_Platform\')},AutoDistribute,Warning,Unsupported platform type,@{utcNow()}',
                                      headers: {
                                        'Log-Type': 'CTI_DistributionHistory_CL'
                                      },
                                      path: '/api/logs'
                                    }
                                  },
                                  Add_to_Processing_Errors: {
                                    runAfter: {
                                      Log_Unsupported_Platform: [
                                        'Succeeded'
                                      ]
                                    },
                                    type: 'AppendToArrayVariable',
                                    inputs: {
                                      name: 'processingErrors',
                                      value: {
                                        indicatorId: '@{item()[12]}',
                                        value: '@{item()[2]}',
                                        error: 'Unsupported platform type',
                                        platform: '@{items(\'For_Each_Target_Platform\')}',
                                        time: '@{utcNow()}'
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          },
                          catch: [
                            {
                              name: 'Distribution_Error',
                              actions: {
                                Log_Distribution_Error: {
                                  type: 'ApiConnection',
                                  inputs: {
                                    host: {
                                      connection: {
                                        name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                      }
                                    },
                                    method: 'post',
                                    body: '@{utcNow()},@{guid()},@{item()[12]},,,@{item()[1]},@{item()[2]},@{items(\'For_Each_Target_Platform\')},Distribution,Error,@{outputs(\'Distribution_Error\')},@{utcNow()}',
                                    headers: {
                                      'Log-Type': 'CTI_DistributionHistory_CL'
                                    },
                                    path: '/api/logs'
                                  }
                                },
                                Add_to_Error_Count: {
                                  runAfter: {
                                    Log_Distribution_Error: [
                                      'Succeeded'
                                    ]
                                  },
                                  type: 'SetVariable',
                                  inputs: {
                                    name: 'processingMetrics',
                                    value: {
                                      totalProcessed: '@{variables(\'processingMetrics\').totalProcessed}',
                                      successCount: '@{variables(\'processingMetrics\').successCount}',
                                      errorCount: '@{add(variables(\'processingMetrics\').errorCount, 1)}',
                                      tierOneCount: '@{variables(\'processingMetrics\').tierOneCount}',
                                      tierTwoCount: '@{variables(\'processingMetrics\').tierTwoCount}',
                                      tierThreeCount: '@{variables(\'processingMetrics\').tierThreeCount}',
                                      startTime: '@{variables(\'processingMetrics\').startTime}'
                                    }
                                  }
                                },
                                Add_Error_to_Array: {
                                  runAfter: {
                                    Add_to_Error_Count: [
                                      'Succeeded'
                                    ]
                                  },
                                  type: 'AppendToArrayVariable',
                                  inputs: {
                                    name: 'processingErrors',
                                    value: {
                                      indicatorId: '@{item()[12]}',
                                      value: '@{item()[2]}',
                                      error: '@{outputs(\'Distribution_Error\')}',
                                      platform: '@{items(\'For_Each_Target_Platform\')}',
                                      time: '@{utcNow()}'
                                    }
                                  }
                                }
                              }
                            }
                          ]
                        }
                      }
                    },
                    
                    Update_Indicator_Status: {
                      runAfter: {
                        For_Each_Target_Platform: [
                          'Succeeded'
                        ]
                      },
                      type: 'ApiConnection',
                      inputs: {
                        body: 'let indicatorId = "@{item()[12]}";\nlet now = now();\nCTI_ThreatIntelIndicator_CL\n| where IndicatorId_g == indicatorId\n| extend EnforcementStatus_s = "Distributed"\n| extend UpdatedTimeUtc_t = now',
                        host: {
                          connection: {
                            name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                          }
                        },
                        method: 'post',
                        path: '/api/logs'
                      }
                    },
                    
                    Increment_Success_Count: {
                      runAfter: {
                        Update_Indicator_Status: [
                          'Succeeded'
                        ]
                      },
                      type: 'SetVariable',
                      inputs: {
                        name: 'processingMetrics',
                        value: {
                          totalProcessed: '@{variables(\'processingMetrics\').totalProcessed}',
                          successCount: '@{add(variables(\'processingMetrics\').successCount, 1)}',
                          errorCount: '@{variables(\'processingMetrics\').errorCount}',
                          tierOneCount: '@{variables(\'processingMetrics\').tierOneCount}',
                          tierTwoCount: '@{variables(\'processingMetrics\').tierTwoCount}',
                          tierThreeCount: '@{variables(\'processingMetrics\').tierThreeCount}',
                          startTime: '@{variables(\'processingMetrics\').startTime}'
                        }
                      }
                    }
                  },
                  else: {
                    actions: {
                      // Tier 2 and Tier 3 indicator processing
                      // Similar pattern as above with added error handling and telemetry
                      // ...
                    }
                  }
                }
              },
              runAfter: {
                Set_Processing_Count: [
                  'Succeeded'
                ]
              },
              type: 'Foreach',
              // Parallel processing for better performance
              operationOptions: 'Sequential',
              // V5: Can be set to Parallel with a specific BatchSize - adjust based on your needs
              // operationOptions: 'Parallel',
              // runtimeConfiguration: {
              //   concurrency: {
              //     repetitions: 10
              //   }
              // }
            },
            
            // Telemetry and operational logging
            Log_Processing_Metrics: {
              runAfter: {
                For_Each_Indicator: [
                  'Succeeded',
                  'Failed',
                  'TimedOut'
                ]
              },
              type: 'If',
              expression: {
                equals: [
                  '@parameters(\'telemetryEnabled\')',
                  true
                ]
              },
              actions: {
                Calculate_Processing_Duration: {
                  runAfter: {},
                  type: 'Compose',
                  inputs: '@{ticks(utcNow())-ticks(variables(\'processingMetrics\').startTime)}'
                },
                Send_Processing_Telemetry: {
                  runAfter: {
                    Calculate_Processing_Duration: [
                      'Succeeded'
                    ]
                  },
                  type: 'ApiConnection',
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                      }
                    },
                    method: 'post',
                    body: '@{utcNow()},@{guid()},@{workflow().name},ProcessingRun,@{variables(\'processingMetrics\').totalProcessed},@{variables(\'processingMetrics\').successCount},@{variables(\'processingMetrics\').errorCount},@{variables(\'processingMetrics\').tierOneCount},@{variables(\'processingMetrics\').tierTwoCount},@{variables(\'processingMetrics\').tierThreeCount},@{outputs(\'Calculate_Processing_Duration\')}',
                    headers: {
                      'Log-Type': 'CTI_TelemetryData_CL'
                    },
                    path: '/api/logs'
                  }
                },
                Log_Processing_Errors: {
                  runAfter: {
                    Send_Processing_Telemetry: [
                      'Succeeded'
                    ]
                  },
                  type: 'If',
                  expression: {
                    greater: [
                      '@length(variables(\'processingErrors\'))',
                      0
                    ]
                  },
                  actions: {
                    Send_Error_Telemetry: {
                      runAfter: {},
                      type: 'ApiConnection',
                      inputs: {
                        host: {
                          connection: {
                            name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                          }
                        },
                        method: 'post',
                        body: '@{string(variables(\'processingErrors\'))}',
                        headers: {
                          'Log-Type': 'CTI_ProcessingErrors_CL'
                        },
                        path: '/api/logs'
                      }
                    }
                  }
                }
              }
            }
          }
        },
        
        // Handle environment health issues
        Health_Check_Failed: {
          runAfter: {
            Check_Environment_Health: [
              'Failed',
              'TimedOut'
            ]
          },
          type: 'ApiConnection',
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
              }
            },
            method: 'post',
            body: '@{utcNow()},@{guid()},@{workflow().name},HealthCheck,Failed,@{outputs(\'Check_Environment_Health\')}',
            headers: {
              'Log-Type': 'CTI_SystemHealth_CL'
            },
            path: '/api/logs'
          }
        }
      }
    },
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

// V5: Operational dashboard to monitor the engine health
resource operationalDashboard 'Microsoft.Portal/dashboards@2020-09-01-preview' = {
  name: '${prefix}-InoculationEngine-Dashboard-${environment}'
  location: location
  tags: union(tags, {
    'hidden-title': 'CTI Inoculation Engine Operational Dashboard'
    Component: 'Monitoring'
    Version: 'V5'
  })
  properties: {
    lenses: {
      '0': {
        order: 0
        parts: {
          '0': {
            position: {
              x: 0
              y: 0
              colSpan: 6
              rowSpan: 4
            }
            metadata: {
              inputs: [
                {
                  name: 'resourceTypeMode'
                  isOptional: true
                  value: 'workspace'
                },
                {
                  name: 'ComponentId'
                  isOptional: true
                  value: {
                    SubscriptionId: subscription().subscriptionId
                    ResourceGroup: resourceGroup().name
                    Name: ctiWorkspaceName
                    ResourceId: ctiWorkspaceId
                  }
                },
                {
                  name: 'Query'
                  isOptional: true
                  value: 'CTI_TelemetryData_CL | where TimeGenerated > ago(24h) | summarize TotalProcessed=sum(Column1), SuccessCount=sum(Column2), ErrorCount=sum(Column3) by bin(TimeGenerated, 1h) | render timechart'
                },
                {
                  name: 'TimeRange'
                  isOptional: true
                  value: 'P1D'
                },
                {
                  name: 'Dimensions'
                  isOptional: true
                  value: {
                    xAxis: {
                      name: 'TimeGenerated',
                      type: 'datetime'
                    },
                    yAxis: [
                      {
                        name: 'TotalProcessed',
                        type: 'real'
                      },
                      {
                        name: 'SuccessCount',
                        type: 'real'
                      },
                      {
                        name: 'ErrorCount',
                        type: 'real'
                      }
                    ],
                    splitBy: [],
                    aggregation: 'Sum'
                  }
                },
                {
                  name: 'Version'
                  isOptional: true
                  value: '1.0'
                },
                {
                  name: 'PartId'
                  isOptional: true
                  value: 'Indicator Processing Status'
                },
                {
                  name: 'PartTitle'
                  isOptional: true
                  value: 'Indicator Processing Status'
                }
              ]
              type: 'Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart'
              settings: {}
            }
          }
          // Additional parts would be defined here
        }
      }
    },
    metadata: {
      model: {
        timeRange: {
          value: {
            relative: {
              duration: 24,
              timeUnit: 1
            }
          },
          type: 'MsPortalFx.Composition.Configuration.ValueTypes.TimeRange'
        }
      }
    }
  }
}

// V5: Enhanced approval workflow with SLA tracking
resource approvalWorkflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: '${prefix}-IndicatorApproval-${environment}'
  location: location
  tags: union(tags, {
    Component: 'Approval Workflow'
    Version: 'V5'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    // Enhanced approval workflow logic
    // ...
  }
}

// Return the deployment information
output inoculationEngineId string = inoculationEngine.id
output inoculationEngineName string = inoculationEngine.name
output dashboardId string = operationalDashboard.id
output approvalWorkflowId string = approvalWorkflow.id
