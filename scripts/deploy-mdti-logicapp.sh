#!/bin/bash
# MDTI Connector Deployment Script

# Set variables (replace with your values)
RESOURCE_GROUP="your-resource-group"
LOCATION="your-location"
MDTI_CONNECTOR_NAME="CTI-MDTI-Connector"
WORKSPACE_NAME="your-law-workspace"
KEY_VAULT_NAME="your-key-vault"
CLIENT_SECRET_NAME="your-client-secret-name"
APP_CLIENT_ID="your-app-client-id"
TENANT_ID="your-tenant-id"

# Get Log Analytics workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $WORKSPACE_NAME \
  --query id -o tsv)

# Get managed identity ID (create it if not exists)
IDENTITY_NAME="CTI-ManagedIdentity"
IDENTITY_ID=$(az identity show \
  --name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv 2>/dev/null || \
  az identity create \
    --name $IDENTITY_NAME \
    --resource-group $RESOURCE_GROUP \
    --query id -o tsv)

# Create Logic App connections (Azure Monitor Logs and Log Analytics Data Collector)
LOGANALYTICS_CONNECTION_NAME="CTI-LogAnalytics-Connection"
LOGANALYTICS_CONNECTION_ID=$(az resource show \
  --resource-group $RESOURCE_GROUP \
  --name $LOGANALYTICS_CONNECTION_NAME \
  --resource-type "Microsoft.Web/connections" \
  --query id -o tsv 2>/dev/null || \
  az resource create \
    --resource-group $RESOURCE_GROUP \
    --resource-type "Microsoft.Web/connections" \
    --name $LOGANALYTICS_CONNECTION_NAME \
    --properties "{\"api\":{\"id\":\"${SUBSCRIPTION_ID}/providers/Microsoft.Web/locations/${LOCATION}/managedApis/azureloganalyticsdatacollector\"},\"displayName\":\"${LOGANALYTICS_CONNECTION_NAME}\",\"parameterValues\":{\"workspaceId\":\"${WORKSPACE_ID}\"}}" \
    --query id -o tsv)

MONITORLOGS_CONNECTION_NAME="CTI-MonitorLogs-Connection"
MONITORLOGS_CONNECTION_ID=$(az resource show \
  --resource-group $RESOURCE_GROUP \
  --name $MONITORLOGS_CONNECTION_NAME \
  --resource-type "Microsoft.Web/connections" \
  --query id -o tsv 2>/dev/null || \
  az resource create \
    --resource-group $RESOURCE_GROUP \
    --resource-type "Microsoft.Web/connections" \
    --name $MONITORLOGS_CONNECTION_NAME \
    --properties "{\"api\":{\"id\":\"${SUBSCRIPTION_ID}/providers/Microsoft.Web/locations/${LOCATION}/managedApis/azuremonitorlogs\"},\"displayName\":\"${MONITORLOGS_CONNECTION_NAME}\"}" \
    --query id -o tsv)

# Deploy the Logic App
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file mdti-connector.bicep \
  --parameters \
    location=$LOCATION \
    mdtiConnectorName=$MDTI_CONNECTOR_NAME \
    managedIdentityId=$IDENTITY_ID \
    logAnalyticsConnectionId=$LOGANALYTICS_CONNECTION_ID \
    logAnalyticsQueryConnectionId=$MONITORLOGS_CONNECTION_ID \
    ctiWorkspaceName=$WORKSPACE_NAME \
    diagnosticSettingsRetentionDays=30 \
    ctiWorkspaceId=$WORKSPACE_ID \
    keyVaultName=$KEY_VAULT_NAME \
    clientSecretName=$CLIENT_SECRET_NAME \
    appClientId=$APP_CLIENT_ID \
    tenantId=$TENANT_ID \
    enableMDTI=true

echo "MDTI Connector Logic App deployment completed"
