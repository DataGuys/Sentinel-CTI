targetScope = 'resourceGroup'

// Core parameters for resource naming and configuration
param prefix string
param environment string
param location string = resourceGroup().location
param tagsMap object = {
  environment: environment
  owner: 'security-team'
  project: 'threat-intelligence'
}

// Resource naming variables with uniqueness for Key Vault
var uniqueSuffix = uniqueString(resourceGroup().id)
var workspaceName = '${prefix}-law-${environment}'
var keyVaultName = toLower(replace('${prefix}-kv-${environment}-${take(uniqueSuffix, 6)}', '-', ''))
var dcrSyslogName = '${prefix}-dcr-syslog-${environment}'
var dceName = '${prefix}-dce-${environment}'

// ==================== Core Resources ====================

// Log Analytics Workspace for threat intelligence data and logs
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
  tags: tagsMap
}

// Key Vault for secure storage of secrets and credentials
// Uses RBAC for access control instead of access policies
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    enableRbacAuthorization: true
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
  }
  tags: tagsMap
}

// ==================== Data Collection Infrastructure ====================

// Data Collection Endpoint for STIX/TAXII feed ingestion
// Exposes an HTTP endpoint for Logic Apps to POST data to
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2021-09-01-preview' = {
  name: dceName
  location: location
  kind: 'AzureMonitor'
  properties: {
    description: 'Endpoint for TAXII/STIX push ingestion'
    networkAcls: {
      publicNetworkAccess: 'Enabled' // Note: Should be restricted in production
    }
  }
  tags: tagsMap
}

// Syslog Collection Rule for standard Linux logs
resource syslogCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrSyslogName
  location: location
  properties: {
    description: 'Syslog collection for CTI'
    dataSources: {
      syslog: [
        {
          streams: ['Microsoft-Syslog']
          facilityNames: [
            'auth'
            'authpriv'
            'daemon'
            'local0'
          ]
          logLevels: [
            'Warning'
            'Notice'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
          name: 'syslogSource'
        }
      ]
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
        streams: ['Microsoft-Syslog']
        destinations: ['lawDest']
      }
    ]
  }
  tags: tagsMap
}

// ==================== Outputs ====================

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = workspaceName
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultName string = keyVaultName
output dceEndpointId string = dataCollectionEndpoint.id
output dceSyslogId string = syslogCollectionRule.id
