param location string
param managedIdentityId string
param logAnalyticsConnectionId string
param logAnalyticsQueryConnectionId string
param microsoftGraphConnectionId string
param ctiWorkspaceName string
param ctiWorkspaceId string
param keyVaultName string
param clientSecretName string
param appClientId string
param tenantId string
param securityApiBaseUrl string
param enableMDTI bool
param enableSecurityCopilot bool
param dceNameForCopilot string
param diagnosticSettingsRetentionDays int
param tags object

// TAXII Connector
module taxiiConnector 'taxii-connector.bicep' = {
  name: 'taxiiConnector'
  params: {
    location: location
    taxiiConnectorLogicAppName: 'CTI-TAXII2-Connector'
    managedIdentityId: managedIdentityId
    logAnalyticsConnectionId: logAnalyticsConnectionId
    logAnalyticsQueryConnectionId: logAnalyticsQueryConnectionId
    ctiWorkspaceName: ctiWorkspaceName
    diagnosticSettingsRetentionDays: diagnosticSettingsRetentionDays
    ctiWorkspaceId: ctiWorkspaceId
    tags: tags
  }
}

// Defender XDR Connector
module defenderConnector 'defender-connector.bicep' = {
  name: 'defenderConnector'
  params: {
    location: location
    defenderConnectorName: 'CTI-DefenderXDR-Connector'
    managedIdentityId: managedIdentityId
    logAnalyticsConnectionId: logAnalyticsConnectionId
    logAnalyticsQueryConnectionId: logAnalyticsQueryConnectionId
    ctiWorkspaceName: ctiWorkspaceName
    diagnosticSettingsRetentionDays: diagnosticSettingsRetentionDays
    ctiWorkspaceId: ctiWorkspaceId
    keyVaultName: keyVaultName
    clientSecretName: clientSecretName
    appClientId: appClientId
    tenantId: tenantId
    securityApiBaseUrl: securityApiBaseUrl
    tags: tags
  }
  dependsOn: [
    taxiiConnector
  ]
}

// MDTI Connector (conditional)
module mdtiConnector 'mdti-connector.bicep' = {
  name: 'mdtiConnector'
  params: {
    location: location
    mdtiConnectorName: 'CTI-MDTI-Connector'
    managedIdentityId: managedIdentityId
    logAnalyticsConnectionId: logAnalyticsConnectionId
    logAnalyticsQueryConnectionId: logAnalyticsQueryConnectionId
    ctiWorkspaceName: ctiWorkspaceName
    diagnosticSettingsRetentionDays: diagnosticSettingsRetentionDays
    ctiWorkspaceId: ctiWorkspaceId
    keyVaultName: keyVaultName
    clientSecretName: clientSecretName
    appClientId: appClientId
    tenantId: tenantId
    enableMDTI: enableMDTI
    tags: tags
  }
  dependsOn: [
    defenderConnector
  ]
}

// Entra ID Connector
module entraConnector 'entra-connector.bicep' = {
  name: 'entraConnector'
  params: {
    location: location
    entraConnectorName: 'CTI-EntraID-Connector'
    managedIdentityId: managedIdentityId
    logAnalyticsConnectionId: logAnalyticsConnectionId
    logAnalyticsQueryConnectionId: logAnalyticsQueryConnectionId
    microsoftGraphConnectionId: microsoftGraphConnectionId
    ctiWorkspaceName: ctiWorkspaceName
    diagnosticSettingsRetentionDays: diagnosticSettingsRetentionDays
    ctiWorkspaceId: ctiWorkspaceId
    graphApiUrl: 'https://graph.microsoft.com'
    tags: tags
  }
  dependsOn: [
    mdtiConnector
  ]
}

// Exchange Online Connector
module exoConnector 'exo-connector.bicep' = {
  name: 'exoConnector'
  params: {
    location: location
    exoConnectorName: 'CTI-ExchangeOnline-Connector'
    managedIdentityId: managedIdentityId
    logAnalyticsConnectionId: logAnalyticsConnectionId
    logAnalyticsQueryConnectionId: logAnalyticsQueryConnectionId
    microsoftGraphConnectionId: microsoftGraphConnectionId
    ctiWorkspaceName: ctiWorkspaceName
    diagnosticSettingsRetentionDays: diagnosticSettingsRetentionDays
    ctiWorkspaceId: ctiWorkspaceId
    tags: tags
  }
  dependsOn: [
    entraConnector
  ]
}

// Security Copilot Connector (conditional)
module securityCopilotConnector 'copilot-connector.bicep' = if (enableSecurityCopilot) {
  name: 'securityCopilotConnector'
  params: {
    location: location
    securityCopilotConnectorName: 'CTI-SecurityCopilot-Connector'
    managedIdentityId: managedIdentityId
    logAnalyticsConnectionId: logAnalyticsConnectionId
    logAnalyticsQueryConnectionId: logAnalyticsQueryConnectionId
    ctiWorkspaceName: ctiWorkspaceName
    diagnosticSettingsRetentionDays: diagnosticSettingsRetentionDays
    ctiWorkspaceId: ctiWorkspaceId
    enableSecurityCopilot: enableSecurityCopilot
    dceNameForCopilot: dceNameForCopilot
    // dceCopilotIntegrationName: dceCopilotIntegrationName // Removed: Parameter not defined in copilot-connector.bicep
    tags: tags
  }
  dependsOn: [
    exoConnector
  ]
}

// Housekeeping Logic App
module housekeeping 'housekeeping.bicep' = {
  name: 'housekeeping'
  params: {
    location: location
    housekeepingName: 'CTI-Housekeeping'
    managedIdentityId: managedIdentityId
    logAnalyticsConnectionId: logAnalyticsConnectionId
    logAnalyticsQueryConnectionId: logAnalyticsQueryConnectionId
    ctiWorkspaceName: ctiWorkspaceName
    diagnosticSettingsRetentionDays: diagnosticSettingsRetentionDays
    ctiWorkspaceId: ctiWorkspaceId
    tags: tags
  }
  dependsOn: enableSecurityCopilot ? [ securityCopilotConnector ] : [ exoConnector ]
}

// Threat Feed Sync Logic App
module threatFeedSync 'threatfeed-sync.bicep' = {
  name: 'threatFeedSync'
  params: {
    location: location
    threatFeedSyncName: 'CTI-ThreatFeedSync'
    managedIdentityId: managedIdentityId
    logAnalyticsConnectionId: logAnalyticsConnectionId
    logAnalyticsQueryConnectionId: logAnalyticsQueryConnectionId
    ctiWorkspaceName: ctiWorkspaceName
    diagnosticSettingsRetentionDays: diagnosticSettingsRetentionDays
    ctiWorkspaceId: ctiWorkspaceId
    tags: tags
  }
  dependsOn: [
    housekeeping
  ]
}

// Output all Logic App names
output logicAppNames object = {
  taxiiConnector: taxiiConnector.outputs.taxiiConnectorName
  defenderConnector: defenderConnector.outputs.defenderConnectorName
  mdtiConnector: enableMDTI ? mdtiConnector.outputs.mdtiConnectorName : ''
  entraConnector: entraConnector.outputs.entraConnectorName
  exoConnector: exoConnector.outputs.exoConnectorName
  securityCopilotConnector: enableSecurityCopilot ? securityCopilotConnector.outputs.securityCopilotConnectorName : ''
  housekeeping: housekeeping.outputs.housekeepingName
  threatFeedSync: threatFeedSync.outputs.threatFeedSyncName
}
