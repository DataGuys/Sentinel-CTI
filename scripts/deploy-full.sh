#!/bin/bash
# Central Threat Intelligence V2 - Full Deployment Script (Fixed)
# This script creates the app registration and deploys the entire solution

set -e

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPO_BRANCH="${REPO_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/DataGuys/CentralThreatIntelligenceV2/${REPO_BRANCH}"
DEPLOY_NAME="cti-$(date +%Y%m%d%H%M%S)"
TEMP_DIR=$(mktemp -d)

echo -e "\n${BLUE}============================================================${NC}"
echo -e "${BLUE}    Central Threat Intelligence V2 - Full Deployment${NC}"
echo -e "${BLUE}============================================================${NC}"

cleanup() {
    echo -e "\n${BLUE}Cleaning up temporary files...${NC}"
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

# Check prerequisites
echo -e "\n${BLUE}Checking prerequisites...${NC}"
command -v az >/dev/null || { echo -e "${RED}❌ Azure CLI not found${NC}"; exit 1; }
command -v jq >/dev/null || { echo -e "${RED}❌ 'jq' is required${NC}"; exit 1; }
command -v curl >/dev/null || { echo -e "${RED}❌ 'curl' is required${NC}"; exit 1; }

# Azure login
if ! az account show &>/dev/null; then
    echo -e "${YELLOW}Not logged in to Azure. Initiating login...${NC}"
    az login --only-show-errors
fi

# Subscription selection - simplified version that works better with piped input
echo -e "\n${BLUE}Getting current subscription...${NC}"
CURRENT_SUB=$(az account show --query "id" -o tsv)
CURRENT_SUB_NAME=$(az account show --query "name" -o tsv)
echo -e "${GREEN}Using subscription: ${CURRENT_SUB_NAME} (${CURRENT_SUB})${NC}"
echo -e "${YELLOW}To use a different subscription, press Ctrl+C and run 'az account set --subscription YOUR_SUB_ID' first${NC}"
sleep 3

# Parse command line arguments
LOCATION=""
PREFIX="cti"
ENVIRONMENT="prod"
TABLE_PLAN="Analytics"

usage() {
    echo -e "Usage: $0 [-l location] [-p prefix] [-e environment] [-t table_plan]"
    echo -e "  -l  Azure region                    (default: first 'Recommended' region or westus2)"
    echo -e "  -p  Resource name prefix            (default: cti)"
    echo -e "  -e  Environment tag                 (default: prod)"
    echo -e "  -t  Table plan: Analytics|Basic|Aux (default: Analytics)"
    echo -e "  -h  Help"
    exit 1
}

while getopts "l:p:e:t:h" opt; do
    case "$opt" in
        l) LOCATION="$OPTARG" ;;
        p) PREFIX="$OPTARG" ;;
        e) ENVIRONMENT="$OPTARG" ;;
        t) TABLE_PLAN="$OPTARG" ;;
        h|*) usage ;;
    esac
done

# Resolve default location if not provided
if [[ -z "$LOCATION" ]]; then
    LOCATION="$(az account list-locations \
                --query "[?metadata.regionCategory=='Recommended'].name | [0]" \
                -o tsv 2>/dev/null || echo westus2)"
fi

# Validate table plan
case "${TABLE_PLAN,,}" in
    analytics|basic|auxiliary) TABLE_PLAN="$(tr '[:lower:]' '[:upper:]' <<< "${TABLE_PLAN:0:1}")${TABLE_PLAN:1}" ;;
    *) echo -e "${RED}❌ Invalid table plan. Use Analytics | Basic | Auxiliary${NC}"; exit 1 ;;
esac

# Set resource group name
RG_NAME="${PREFIX}-rg-${ENVIRONMENT}"

echo -e "\n${BLUE}======================= Configuration =======================${NC}"
echo -e " Subscription : ${CURRENT_SUB_NAME}"
echo -e " Location     : ${LOCATION}"
echo -e " Prefix       : ${PREFIX}"
echo -e " Environment  : ${ENVIRONMENT}"
echo -e " Table plan   : ${TABLE_PLAN}"
echo -e " Resource Group: ${RG_NAME}"
echo -e " Deployment   : ${DEPLOY_NAME}"
echo -e "${BLUE}============================================================${NC}"

# Step 1: Create the app registration
echo -e "\n${BLUE}Step 1: Creating app registration...${NC}"
curl -sL "${RAW_BASE}/scripts/create-cti-app-registration.sh" -o "${TEMP_DIR}/create-app.sh"
chmod +x "${TEMP_DIR}/create-app.sh"
cd "${TEMP_DIR}" && ./create-app.sh

# Get app credentials from file
if [[ -f "${TEMP_DIR}/cti-app-credentials.env" ]]; then
    source "${TEMP_DIR}/cti-app-credentials.env"
    echo -e "${GREEN}✅ App registration created successfully${NC}"
    echo -e "    App ID: ${CLIENT_ID}"
else
    echo -e "${RED}❌ Failed to create app registration${NC}"
    exit 1
fi

# Step 2: Download Bicep files
echo -e "\n${BLUE}Step 2: Downloading deployment files...${NC}"
mkdir -p "${TEMP_DIR}/modules"
mkdir -p "${TEMP_DIR}/logic-apps"
mkdir -p "${TEMP_DIR}/tables"

# Main Bicep file
curl -sL "${RAW_BASE}/main.bicep" -o "${TEMP_DIR}/main.bicep"
# Modules - download fixed versions
curl -sL "${RAW_BASE}/modules/resources.bicep" -o "${TEMP_DIR}/modules/resources.bicep"
# Tables
curl -sL "${RAW_BASE}/tables/custom-tables.json" -o "${TEMP_DIR}/tables/custom-tables.json"

# Create custom modules for phased deployment
cat > "${TEMP_DIR}/modules/custom-tables.bicep" << 'EOT'
@description('Name of the Log Analytics workspace')
param workspaceName string

@description('Table plan: Analytics, Basic, or Standard')
@allowed(['Analytics', 'Basic', 'Standard'])
param tablePlan string = 'Analytics'

@description('Location for all resources')
param location string = resourceGroup().location

var ctiTables = [
  {
    name: 'CTI_ThreatIntelIndicator_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'Type_s', type: 'string' }
      { name: 'Value_s', type: 'string' }
      { name: 'Pattern_s', type: 'string' }
      { name: 'PatternType_s', type: 'string' }
      { name: 'Name_s', type: 'string' }
      { name: 'Description_s', type: 'string' }
      { name: 'Action_s', type: 'string' }
      { name: 'Confidence_d', type: 'string' }
      { name: 'ValidFrom_t', type: 'datetime' }
      { name: 'ValidUntil_t', type: 'datetime' }
      { name: 'CreatedTimeUtc_t', type: 'datetime' }
      { name: 'UpdatedTimeUtc_t', type: 'datetime' }
      { name: 'Source_s', type: 'string' }
      { name: 'SourceRef_s', type: 'string' }
      { name: 'KillChainPhases_s', type: 'string' }
      { name: 'Labels_s', type: 'string' }
      { name: 'ThreatType_s', type: 'string' }
      { name: 'TLP_s', type: 'string' }
      { name: 'DistributionTargets_s', type: 'string' }
      { name: 'ThreatActorName_s', type: 'string' }
      { name: 'CampaignName_s', type: 'string' }
      { name: 'Active_b', type: 'bool' }
      { name: 'ObjectId_g', type: 'guid' }
      { name: 'IndicatorId_g', type: 'guid' }
    ]
  }
  {
    name: 'CTI_IPIndicators_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'IPAddress_s', type: 'string' }
      { name: 'ConfidenceScore_d', type: 'string' }
      { name: 'SourceFeed_s', type: 'string' }
      { name: 'FirstSeen_t', type: 'datetime' }
      { name: 'LastSeen_t', type: 'datetime' }
      { name: 'ExpirationDateTime_t', type: 'datetime' }
      { name: 'ThreatType_s', type: 'string' }
      { name: 'ThreatCategory_s', type: 'string' }
      { name: 'TLP_s', type: 'string' }
      { name: 'GeoLocation_s', type: 'string' }
      { name: 'ASN_s', type: 'string' }
      { name: 'Tags_s', type: 'string' }
      { name: 'Description_s', type: 'string' }
      { name: 'Action_s', type: 'string' }
      { name: 'ReportedBy_s', type: 'string' }
      { name: 'DistributionTargets_s', type: 'string' }
      { name: 'ThreatActorName_s', type: 'string' }
      { name: 'CampaignName_s', type: 'string' }
      { name: 'Active_b', type: 'bool' }
      { name: 'IndicatorId_g', type: 'guid' }
    ]
  }
  {
    name: 'CTI_DomainIndicators_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'Domain_s', type: 'string' }
      { name: 'ConfidenceScore_d', type: 'string' }
      { name: 'SourceFeed_s', type: 'string' }
      { name: 'FirstSeen_t', type: 'datetime' }
      { name: 'LastSeen_t', type: 'datetime' }
      { name: 'ExpirationDateTime_t', type: 'datetime' }
      { name: 'ThreatType_s', type: 'string' }
      { name: 'ThreatCategory_s', type: 'string' }
      { name: 'TLP_s', type: 'string' }
      { name: 'Tags_s', type: 'string' }
      { name: 'Description_s', type: 'string' }
      { name: 'Action_s', type: 'string' }
      { name: 'DistributionTargets_s', type: 'string' }
      { name: 'ReportedBy_s', type: 'string' }
      { name: 'ThreatActorName_s', type: 'string' }
      { name: 'CampaignName_s', type: 'string' }
      { name: 'Active_b', type: 'bool' }
      { name: 'IndicatorId_g', type: 'guid' }
    ]
  }
  {
    name: 'CTI_URLIndicators_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'URL_s', type: 'string' }
      { name: 'ConfidenceScore_d', type: 'string' }
      { name: 'SourceFeed_s', type: 'string' }
      { name: 'FirstSeen_t', type: 'datetime' }
      { name: 'LastSeen_t', type: 'datetime' }
      { name: 'ExpirationDateTime_t', type: 'datetime' }
      { name: 'ThreatType_s', type: 'string' }
      { name: 'ThreatCategory_s', type: 'string' }
      { name: 'TLP_s', type: 'string' }
      { name: 'Tags_s', type: 'string' }
      { name: 'Description_s', type: 'string' }
      { name: 'Action_s', type: 'string' }
      { name: 'DistributionTargets_s', type: 'string' }
      { name: 'ReportedBy_s', type: 'string' }
      { name: 'ThreatActorName_s', type: 'string' }
      { name: 'CampaignName_s', type: 'string' }
      { name: 'Active_b', type: 'bool' }
      { name: 'IndicatorId_g', type: 'guid' }
    ]
  }
  {
    name: 'CTI_FileHashIndicators_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'SHA256_s', type: 'string' }
      { name: 'MD5_s', type: 'string' }
      { name: 'SHA1_s', type: 'string' }
      { name: 'ConfidenceScore_d', type: 'string' }
      { name: 'SourceFeed_s', type: 'string' }
      { name: 'FirstSeen_t', type: 'datetime' }
      { name: 'LastSeen_t', type: 'datetime' }
      { name: 'ExpirationDateTime_t', type: 'datetime' }
      { name: 'MalwareFamily_s', type: 'string' }
      { name: 'ThreatType_s', type: 'string' }
      { name: 'ThreatCategory_s', type: 'string' }
      { name: 'TLP_s', type: 'string' }
      { name: 'Tags_s', type: 'string' }
      { name: 'Description_s', type: 'string' }
      { name: 'Action_s', type: 'string' }
      { name: 'DistributionTargets_s', type: 'string' }
      { name: 'ReportedBy_s', type: 'string' }
      { name: 'ThreatActorName_s', type: 'string' }
      { name: 'CampaignName_s', type: 'string' }
      { name: 'Active_b', type: 'bool' }
      { name: 'IndicatorId_g', type: 'guid' }
    ]
  }
  {
    name: 'CTI_StixData_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'RawSTIX', type: 'string' }
      { name: 'STIXType', type: 'string' }
      { name: 'STIXId', type: 'string' }
      { name: 'CreatedBy', type: 'string' }
      { name: 'Source', type: 'string' }
    ]
  }
]

// Create custom tables in the Log Analytics workspace
resource customTables 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = [for table in ctiTables: {
  name: '${workspaceName}/${table.name}'
  properties: {
    schema: {
      name: table.name
      columns: table.columns
    }
    retentionInDays: 30
    plan: tablePlan
  }
}]

output tableNames array = [for (table, i) in ctiTables: table.name]
EOT

cat > "${TEMP_DIR}/modules/stix-dcr.bicep" << 'EOT'
param location string
param workspaceName string
param dceId string
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
    dataCollectionEndpointId: dceId
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
EOT

# Fix resources.bicep with unique Key Vault naming
cat > "${TEMP_DIR}/modules/resources.bicep" << 'EOT'
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
var dcrStixName = '${prefix}-dcr-stix-${environment}'
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
          // Fixed: Added streams property
          streams: ['Microsoft-Syslog']
          facilityNames: [
            'auth'
            'authpriv'
            'daemon'
            'local0'
          ]
          logLevels: [
            // Fixed: Using valid log level values
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
EOT

echo -e "${GREEN}✅ Deployment files downloaded and updated${NC}"

# Step 3: Deploy the infrastructure
echo -e "\n${BLUE}Step 3: Deploying infrastructure...${NC}"
cd "${TEMP_DIR}"

# Step 3a: Create resource group
echo -e "${YELLOW}Creating resource group ${RG_NAME}...${NC}"
az group create --name "${RG_NAME}" --location "${LOCATION}" --tags "project=CentralThreatIntelligence" "environment=${ENVIRONMENT}"

# Wait for resource group to be fully provisioned
echo -e "${YELLOW}Waiting for resource group to be fully provisioned...${NC}"
sleep 10

# Verify resource group exists
if ! az group show --name "${RG_NAME}" &>/dev/null; then
    echo -e "${RED}❌ Resource group ${RG_NAME} was not created successfully${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Resource group ${RG_NAME} created successfully${NC}"

# Step 3b: Deploy core resources with fixed Key Vault naming
echo -e "${YELLOW}Deploying core resources (workspace, key vault, DCE)...${NC}"
CORE_DEPLOY=$(az deployment group create \
    --name "${DEPLOY_NAME}-core" \
    --resource-group "${RG_NAME}" \
    --template-file "./modules/resources.bicep" \
    --parameters prefix="${PREFIX}" environment="${ENVIRONMENT}" location="${LOCATION}" \
    --query "properties.outputs" -o json)

# Get outputs from deployment
WORKSPACE_NAME=$(echo "$CORE_DEPLOY" | jq -r '.workspaceName.value')
KEYVAULT_NAME=$(echo "$CORE_DEPLOY" | jq -r '.keyVaultName.value')
DCE_ID=$(echo "$CORE_DEPLOY" | jq -r '.dceEndpointId.value')

if [[ -z "$WORKSPACE_NAME" ]]; then
    echo -e "${RED}❌ Failed to retrieve workspace name from deployment${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Core infrastructure deployed successfully${NC}"
echo -e "    Resource Group: ${RG_NAME}"
echo -e "    Workspace Name: ${WORKSPACE_NAME}"
echo -e "    Key Vault Name: ${KEYVAULT_NAME}"

# Step 4: Create custom tables
echo -e "\n${BLUE}Step 4: Creating custom Log Analytics tables...${NC}"
echo -e "${YELLOW}Deploying custom tables...${NC}"

# Deploy custom tables using Bicep
TABLE_DEPLOY=$(az deployment group create \
    --name "${DEPLOY_NAME}-tables" \
    --resource-group "${RG_NAME}" \
    --template-file "./modules/custom-tables.bicep" \
    --parameters workspaceName="${WORKSPACE_NAME}" tablePlan="${TABLE_PLAN}" location="${LOCATION}" \
    --query "properties.outputs" -o json)

echo -e "${GREEN}✅ Custom tables created with ${TABLE_PLAN} tier${NC}"

# Step 5: Deploy STIX DCR now that tables exist
echo -e "\n${BLUE}Step 5: Deploying STIX DCR now that tables exist...${NC}"
STIX_DEPLOY=$(az deployment group create \
    --name "${DEPLOY_NAME}-stix-dcr" \
    --resource-group "${RG_NAME}" \
    --template-file "./modules/stix-dcr.bicep" \
    --parameters workspaceName="${WORKSPACE_NAME}" location="${LOCATION}" dceId="${DCE_ID}" \
    --query "properties.outputs" -o json)

echo -e "${GREEN}✅ STIX DCR deployed successfully${NC}"

# Step 6: Deploy Logic Apps
echo -e "\n${BLUE}Step 6: Deploying Logic App connectors...${NC}"

# Ensure we have the workspace ID
WORKSPACE_ID=$(echo "$CORE_DEPLOY" | jq -r '.workspaceId.value')
if [[ -z "$WORKSPACE_ID" ]]; then
    echo -e "${RED}❌ Failed to retrieve workspace ID from deployment${NC}"
    exit 1
fi

# Create user-assigned managed identity for logic apps
echo -e "${YELLOW}Creating user-assigned managed identity for logic apps...${NC}"
IDENTITY_NAME="CTI-ManagedIdentity"
IDENTITY_ID=$(az identity show \
  --name $IDENTITY_NAME \
  --resource-group "$RG_NAME" \
  --query id -o tsv 2>/dev/null || \
  az identity create \
    --name $IDENTITY_NAME \
    --resource-group "$RG_NAME" \
    --location "$LOCATION" \
    --tags "project=CentralThreatIntelligence" "environment=$ENVIRONMENT" \
    --query id -o tsv)

# Get the managed identity's principal ID
IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name $IDENTITY_NAME \
  --resource-group "$RG_NAME" \
  --query principalId -o tsv)

# Store app registration client secret in Key Vault
echo -e "${YELLOW}Storing app registration client secret in Key Vault...${NC}"
CLIENT_SECRET_NAME="CTI-APP-SECRET"
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "$CLIENT_SECRET_NAME" \
    --value "$CLIENT_SECRET" \
    --output none

# Grant the managed identity access to the Key Vault to read secrets
echo -e "${YELLOW}Granting managed identity access to Key Vault...${NC}"
az role assignment create \
    --assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Key Vault Secrets User" \
    --scope "$(az keyvault show --name $KEYVAULT_NAME --query id -o tsv)" \
    --output none

# Create JSON tags object properly
TAGS_JSON=$(jq -n --arg env "$ENVIRONMENT" '{"project":"CentralThreatIntelligence","environment":$env}')

# Deploy logic apps using deployment.bicep
echo -e "${YELLOW}Deploying logic apps using Bicep templates...${NC}"
LOGIC_APPS_DEPLOY=$(az deployment group create \
  --resource-group "$RG_NAME" \
  --name "${DEPLOY_NAME}-logic-apps" \
  --template-file "${TEMP_DIR}/logic-apps/deployment.bicep" \
  --parameters \
    location="$LOCATION" \
    managedIdentityId="$IDENTITY_ID" \
    logAnalyticsConnectionId="$LOGANALYTICS_CONNECTION_ID" \
    logAnalyticsQueryConnectionId="$MONITORLOGS_CONNECTION_ID" \
    microsoftGraphConnectionId="$GRAPH_CONNECTION_ID" \
    ctiWorkspaceName="$WORKSPACE_NAME" \
    ctiWorkspaceId="$WORKSPACE_ID" \
    keyVaultName="$KEYVAULT_NAME" \
    clientSecretName="$CLIENT_SECRET_NAME" \
    appClientId="$CLIENT_ID" \
    tenantId="$TENANT_ID" \
    securityApiBaseUrl="https://api.securitycenter.microsoft.com" \
    enableMDTI=true \
    enableSecurityCopilot=true \
    dceNameForCopilot="${PREFIX}-dce-copilot-${ENVIRONMENT}" \
    diagnosticSettingsRetentionDays=30 \
    tags="$TAGS_JSON" \
    --query "properties.outputs" -o json)
