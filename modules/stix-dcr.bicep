param location string
param workspaceName string
param dceEndpointId string
param dcrStixName string = 'cti-dcr-stix-prod'
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

// STIX Data Collection Rule - created after tables exist
resource stixCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrStixName
  location: location
  properties: {
    dataCollectionEndpointId: dceEndpointId
    description: 'Custom log ingestion for TAXII/STIX feeds (JSON)'
    streamDeclarations: {
      'Custom-CTI_StixData_CL': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'RawSTIX'
            type: 'string'
          }
          {
            name: 'STIXType'
            type: 'string'
          }
          {
            name: 'STIXId'
            type: 'string'
          }
          {
            name: 'CreatedBy'
            type: 'string'
          }
          {
            name: 'Source'
            type: 'string'
          }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          name: 'lawDest'
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Custom-CTI_StixData_CL']
        destinations: ['lawDest']
      }
    ]
  }
  tags: tags
}

output stixDcrId string = stixCollectionRule.id
