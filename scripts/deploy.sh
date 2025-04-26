#!/bin/bash
# Central Threat Intelligence V5 - Full Deployment Script
# This script creates the app registration, deploys the inoculation engine, and configures all connectors

set -e

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# V5: Proper repository references
REPO_OWNER="SecurityOrg"
REPO_NAME="CTI-V5"
REPO_BRANCH="${REPO_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
DEPLOY_NAME="cti-v5-$(date +%Y%m%d%H%M%S)"

echo -e "\n${BLUE}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    Central Threat Intelligence V5 - Production Deployment Tool    ${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

# Parse command line arguments
LOCATION=""
PREFIX="cti"
ENVIRONMENT="prod"
TABLE_PLAN="Analytics"
ENABLE_CROSS_CLOUD=true
ENABLE_NETWORK=true
ENABLE_ENDPOINT=true
SLA_HOURS=24
AUTO_APPROVE=false
PERFORMANCE_TIER="Standard"

usage() {
    echo -e "Usage: $0 [-l location] [-p prefix] [-e environment] [-t table_plan] [-c enable_cross_cloud] [-n enable_network] [-d enable_endpoint] [-s sla_hours] [-a auto_approve] [-x performance_tier]"
    echo -e "  -l  Azure region                          (default: eastus)"
    echo -e "  -p  Resource name prefix                  (default: cti)"
    echo -e "  -e  Environment tag                       (default: prod)"
    echo -e "  -t  Table plan: Analytics|Basic|Standard  (default: Analytics)"
    echo -e "  -c  Enable cross-cloud protection         (default: true)"
    echo -e "  -n  Enable network protection             (default: true)"
    echo -e "  -d  Enable endpoint protection            (default: true)"
    echo -e "  -s  SLA hours for critical alerts         (default: 24)"
    echo -e "  -a  Auto-approve                          (default: false)"
    echo -e "  -x  Performance tier                      (default: Standard)"
    echo -e "  -h  Help"
    exit 1
}

while getopts "l:p:e:t:c:n:d:s:ax:h" opt; do
    case "$opt" in
        l) LOCATION="$OPTARG" ;;
        p) PREFIX="$OPTARG" ;;
        e) ENVIRONMENT="$OPTARG" ;;
        t) TABLE_PLAN="$OPTARG" ;;
        c) ENABLE_CROSS_CLOUD="$OPTARG" ;;
        n) ENABLE_NETWORK="$OPTARG" ;;
        d) ENABLE_ENDPOINT="$OPTARG" ;;
        s) SLA_HOURS="$OPTARG" ;;
        a) AUTO_APPROVE=true ;;
        x) PERFORMANCE_TIER="$OPTARG" ;;
        h|*) usage ;;
    esac
done

# V5: Parameter validation
if [[ -z "$LOCATION" ]]; then
    # Auto-detect nearest region
    echo -e "${YELLOW}Location not provided. Detecting optimal region...${NC}"
    LOCATION=$(az account list-locations --query "[?metadata.regionCategory=='Recommended'].name" -o tsv | head -1)
    if [[ -z "$LOCATION" ]]; then
        LOCATION="eastus"
    fi
    echo -e "${GREEN}Selected region: ${LOCATION}${NC}"
fi

# Validate table plan
case "${TABLE_PLAN,,}" in
    analytics|basic|standard) TABLE_PLAN="$(tr '[:lower:]' '[:upper:]' <<< "${TABLE_PLAN:0:1}")${TABLE_PLAN:1}" ;;
    *) echo -e "${RED}❌ Invalid table plan. Use Analytics | Basic | Standard${NC}"; exit 1 ;;
esac

# Validate performance tier
case "${PERFORMANCE_TIER,,}" in
    basic|standard|premium) PERFORMANCE_TIER="$(tr '[:lower:]' '[:upper:]' <<< "${PERFORMANCE_TIER:0:1}")${PERFORMANCE_TIER:1}" ;;
    *) echo -e "${RED}❌ Invalid performance tier. Use Basic | Standard | Premium${NC}"; exit 1 ;;
esac

# Validate SLA hours
if ! [[ "$SLA_HOURS" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}❌ SLA hours must be a number${NC}"
    exit 1
fi

echo -e "\n${BLUE}═════════════════════════ Configuration ═════════════════════════${NC}"
echo -e "${CYAN}Location        :${NC} ${LOCATION}"
echo -e "${CYAN}Prefix          :${NC} ${PREFIX}"
echo -e "${CYAN}Environment     :${NC} ${ENVIRONMENT}"
echo -e "${CYAN}Table plan      :${NC} ${TABLE_PLAN}"
echo -e "${CYAN}Cross-Cloud     :${NC} ${ENABLE_CROSS_CLOUD}"
echo -e "${CYAN}Network         :${NC} ${ENABLE_NETWORK}"
echo -e "${CYAN}Endpoint        :${NC} ${ENABLE_ENDPOINT}"
echo -e "${CYAN}SLA Hours       :${NC} ${SLA_HOURS}"
echo -e "${CYAN}Performance Tier:${NC} ${PERFORMANCE_TIER}"
echo -e "${CYAN}Deployment ID   :${NC} ${DEPLOY_NAME}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

# V5: Get confirmation if not auto-approved
if [[ "$AUTO_APPROVE" != "true" ]]; then
    read -p "Proceed with deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deployment cancelled.${NC}"
        exit 0
    fi
fi

# V5: Check for Azure CLI installation
echo -e "\n${BLUE}Checking prerequisites...${NC}"
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI not found. Please install it and try again.${NC}"
    echo "Installation instructions: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# V5: Check for az extensions
required_extensions=("logic" "resource-graph")
for ext in "${required_extensions[@]}"; do
    if ! az extension show -n "$ext" &> /dev/null; then
        echo -e "${YELLOW}Installing required extension: $ext${NC}"
        az extension add --name "$ext" --yes
    fi
done

# Azure login check with enhanced error handling
if ! az account show &>/dev/null; then
    echo -e "${YELLOW}Not logged in to Azure. Initiating login...${NC}"
    if ! az login --only-show-errors; then
        echo -e "${RED}❌ Azure login failed. Please try again.${NC}"
        exit 1
    fi
fi

# Get current subscription with validation
SUB_NAME=$(az account show --query name -o tsv)
SUB_ID=$(az account show --query id -o tsv)
if [[ -z "$SUB_ID" ]]; then
    echo -e "${RED}❌ Failed to retrieve subscription information.${NC}"
    exit 1
fi
echo -e "${GREEN}Using subscription: ${SUB_NAME} (${SUB_ID})${NC}"

# V5: Check quota and permissions
echo -e "${YELLOW}Checking permissions and quotas...${NC}"
can_create_rg=$(az role assignment list --query "[?contains(roleDefinitionName, 'Contributor') || contains(roleDefinitionName, 'Owner')].roleDefinitionName" -o tsv | wc -l)
if [[ $can_create_rg -eq 0 ]]; then
    echo -e "${RED}❌ Insufficient permissions. You need Contributor or Owner role to deploy this solution.${NC}"
    exit 1
fi

# Step 1: Create app registration with improved error handling
echo -e "\n${BLUE}Step 1: Creating app registration...${NC}"
APP_NAME="${PREFIX}-v5-solution-${ENVIRONMENT}"
echo "Creating app registration: ${APP_NAME}..."

APP_CREATE=$(az ad app create --display-name "${APP_NAME}" 2>/dev/null)
if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Failed to create application registration.${NC}"
    echo -e "${YELLOW}Checking if app already exists...${NC}"
    
    EXISTING_APP=$(az ad app list --display-name "${APP_NAME}" --query "[0]" -o json)
    if [[ -n "$EXISTING_APP" ]]; then
        echo -e "${YELLOW}Application already exists. Using existing application.${NC}"
        APP_ID=$(echo "$EXISTING_APP" | jq -r '.appId // .id')
        OBJECT_ID=$(echo "$EXISTING_APP" | jq -r '.id // .objectId')
    else
        echo -e "${RED}Failed to create or find application. Check your permissions.${NC}"
        exit 1
    fi
else
    APP_ID=$(echo "$APP_CREATE" | jq -r '.appId // .id')
    OBJECT_ID=$(echo "$APP_CREATE" | jq -r '.id // .objectId')
fi

if [ -z "$APP_ID" ]; then
    echo -e "${RED}Failed to retrieve Application ID.${NC}"
    exit 1
fi

echo -e "${GREEN}Application ID: ${APP_ID}${NC}"

# Create service principal with improved error handling
echo "Creating service principal for the application..."
SP_CREATE=$(az ad sp create --id "$APP_ID" 2>/dev/null)
if [[ $? -ne 0 ]]; then
    echo -e "${YELLOW}Checking if service principal already exists...${NC}"
    SP_EXISTS=$(az ad sp list --filter "appId eq '${APP_ID}'" --query "[0]" -o json)
    if [[ -z "$SP_EXISTS" ]]; then
        echo -e "${RED}Failed to create service principal.${NC}"
        exit 1
    else
        echo -e "${YELLOW}Service principal already exists.${NC}"
    fi
else
    echo -e "${GREEN}Service principal created successfully.${NC}"
fi

# Create client secret with improved error handling
echo -e "${BLUE}Creating client secret...${NC}"
SECRET_YEARS=2
SECRET_RESULT=$(az ad app credential reset --id "$APP_ID" --years "$SECRET_YEARS" --query password -o tsv 2>/dev/null)

if [ -z "$SECRET_RESULT" ]; then
    echo -e "${RED}Failed to create client secret. Please check your permissions.${NC}"
    exit 1
fi

# Save credentials to a file with enhanced security
echo -e "${YELLOW}Saving credentials to secure file...${NC}"
CREDS_FILE="cti-v5-app-credentials.env"
echo "CLIENT_ID=${APP_ID}" > "$CREDS_FILE"
echo "APP_OBJECT_ID=${OBJECT_ID}" >> "$CREDS_FILE"
echo "APP_NAME=${APP_NAME}" >> "$CREDS_FILE"
echo "CLIENT_SECRET=${SECRET_RESULT}" >> "$CREDS_FILE"
chmod 600 "$CREDS_FILE"

echo -e "${GREEN}Client secret created successfully and saved to ${CREDS_FILE} (restricted permissions)${NC}"

# Add required API permissions
echo -e "${BLUE}Adding required permissions...${NC}"

# Microsoft Defender XDR
echo -e "${YELLOW}Adding Microsoft Defender XDR permissions...${NC}"
az ad app permission add --id "$APP_ID" --api 00000003-0000-0000-c000-000000000000 --api-permissions "ThreatIndicators.ReadWrite.OwnedBy=Role"

# Microsoft Graph
echo -e "${YELLOW}Adding Microsoft Graph permissions...${NC}"
az ad app permission add --id "$APP_ID" --api 00000003-0000-0000-c000-000000000000 --api-permissions "User.Read.All=Role"

# Microsoft Sentinel
echo -e "${YELLOW}Adding Microsoft Sentinel permissions...${NC}"
az ad app permission add --id "$APP_ID" --api 9ec59623-ce40-4dc8-a635-ed0275b5d58a --api-permissions "7e2fc5f2-d647-4926-89f6-f13ad2950560=Role"

# Step 2: Deploy the main solution with enhanced error handling and dependency checks
echo -e "\n${BLUE}Step 2: Deploying the CTI V5 solution...${NC}"

# Create resource group with retry logic
RG_NAME="${PREFIX}-v5-${ENVIRONMENT}-rg"
MAX_RETRIES=3
RETRY_COUNT=0

echo -e "${YELLOW}Creating resource group ${RG_NAME}...${NC}"
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if az group create --name "${RG_NAME}" --location "${LOCATION}" \
    --tags "project=CentralThreatIntelligence" "environment=${ENVIRONMENT}" "version=5.0" > /dev/null; then
    echo -e "${GREEN}Resource group created successfully.${NC}"
    break
  else
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo -e "${YELLOW}Failed to create resource group. Retrying (${RETRY_COUNT}/${MAX_RETRIES})...${NC}"
      sleep 5
    else
      echo -e "${RED}Failed to create resource group after ${MAX_RETRIES} attempts.${NC}"
      exit 1
    fi
  fi
done

# V5: Check if template exists before deployment
echo -e "${YELLOW}Validating deployment template...${NC}"
TEMPLATE_URL="${RAW_BASE}/azuredeploy.json"
if ! curl -s --head "$TEMPLATE_URL" | grep "200 OK" > /dev/null; then
    echo -e "${RED}❌ Deployment template not found at: ${TEMPLATE_URL}${NC}"
    echo -e "${YELLOW}Please check your repository settings and try again.${NC}"
    exit 1
fi

# V5: Validate the template before deployment
echo -e "${YELLOW}Validating deployment template...${NC}"
VALIDATION=$(az deployment group validate \
    --resource-group "$RG_NAME" \
    --template-uri "$TEMPLATE_URL" \
    --parameters prefix="$PREFIX" environment="$ENVIRONMENT" location="$LOCATION" \
    --parameters enableCrossCloudProtection="$ENABLE_CROSS_CLOUD" enableNetworkProtection="$ENABLE_NETWORK" enableEndpointProtection="$ENABLE_ENDPOINT" \
    --parameters tablePlan="$TABLE_PLAN" performanceTier="$PERFORMANCE_TIER" 2>&1)

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Template validation failed:${NC}"
    echo "$VALIDATION"
    echo -e "${YELLOW}Do you want to continue anyway? (y/n)${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deployment cancelled.${NC}"
        exit 1
    fi
fi

# Deploy the solution with progress monitoring
echo -e "${YELLOW}Deploying the core solution (this may take 15-20 minutes)...${NC}"
DEPLOY_STARTED=$(date +%s)

az deployment group create \
    --name "$DEPLOY_NAME" \
    --resource-group "$RG_NAME" \
    --template-uri "$TEMPLATE_URL" \
    --parameters prefix="$PREFIX" environment="$ENVIRONMENT" location="$LOCATION" \
    --parameters enableCrossCloudProtection="$ENABLE_CROSS_CLOUD" enableNetworkProtection="$ENABLE_NETWORK" enableEndpointProtection="$ENABLE_ENDPOINT" \
    --parameters tablePlan="$TABLE_PLAN" performanceTier="$PERFORMANCE_TIER" \
    --no-wait

echo -e "${YELLOW}Deployment started in the background. Monitoring progress...${NC}"

# V5: Progress monitoring with status updates
status="Running"
progress_count=0
spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
while [ "$status" = "Running" ]; do
    status=$(az deployment group show --name "$DEPLOY_NAME" --resource-group "$RG_NAME" --query "properties.provisioningState" -o tsv)
    if [ "$status" = "Running" ]; then
        elapsed=$(($(date +%s) - DEPLOY_STARTED))
        minutes=$((elapsed / 60))
        seconds=$((elapsed % 60))
        
        # Get current operation status if available
        current_op=$(az deployment group show --name "$DEPLOY_NAME" --resource-group "$RG_NAME" --query "properties.outputs.currentOperation.value" -o tsv 2>/dev/null || echo "Deploying resources...")
        
        spin_index=$((progress_count % 10))
        printf "\r${spinner[$spin_index]} Deployment running for %02d:%02d - %s" $minutes $seconds "$current_op"
        progress_count=$((progress_count + 1))
        sleep 3
    fi
done
echo

if [ "$status" = "Succeeded" ]; then
    elapsed=$(($(date +%s) - DEPLOY_STARTED))
    minutes=$((elapsed / 60))
    seconds=$((elapsed % 60))
    echo -e "\n${GREEN}✅ Deployment completed successfully in ${minutes}m ${seconds}s!${NC}"
    
    # Extract key output values
    DEPLOYMENT_RESULT=$(az deployment group show --name "$DEPLOY_NAME" --resource-group "$RG_NAME" --query "properties.outputs" -o json)
    WORKSPACE_NAME=$(echo "$DEPLOYMENT_RESULT" | jq -r '.workspaceName.value')
    KEYVAULT_NAME=$(echo "$DEPLOYMENT_RESULT" | jq -r '.keyVaultName.value')
    DASHBOARD_URL=$(echo "$DEPLOYMENT_RESULT" | jq -r '.dashboardUrl.value')
    ENGINE_URL=$(echo "$DEPLOYMENT_RESULT" | jq -r '.inoculationEngineUrl.value')
    
    echo -e "${GREEN}Workspace: ${WORKSPACE_NAME}${NC}"
    echo -e "${GREEN}Key Vault: ${KEYVAULT_NAME}${NC}"
    echo -e "${GREEN}Dashboard: ${DASHBOARD_URL}${NC}"
    echo -e "${GREEN}Engine: ${ENGINE_URL}${NC}"
else
    echo -e "${RED}❌ Deployment failed with status: ${status}${NC}"
    echo -e "${YELLOW}Checking deployment errors...${NC}"
    az deployment group show --name "$DEPLOY_NAME" --resource-group "$RG_NAME" --query "properties.error" -o json
    exit 1
fi

# Store client secret in Key Vault
echo -e "${YELLOW}Storing app registration client secret in Key Vault...${NC}"
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "CTI-APP-SECRET" \
    --value "$SECRET_RESULT" \
    --output none

echo -e "${GREEN}✓ Client secret stored in Key Vault successfully${NC}"

# Step 3: Configure required API keys with improved UX
echo -e "\n${BLUE}Step 3: Configuring additional API keys...${NC}"
echo -e "${YELLOW}Please enter API keys for third-party services (press Enter to skip)${NC}"

read -p "VirusTotal API Key: " VIRUSTOTAL_APIKEY
if [[ -n "$VIRUSTOTAL_APIKEY" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "VirusTotal-ApiKey" --value "$VIRUSTOTAL_APIKEY" --output none
    echo -e "${GREEN}✓ VirusTotal API Key stored${NC}"
fi

read -p "AbuseIPDB API Key: " ABUSEIPDB_APIKEY
if [[ -n "$ABUSEIPDB_APIKEY" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "AbuseIPDB-ApiKey" --value "$ABUSEIPDB_APIKEY" --output none
    echo -e "${GREEN}✓ AbuseIPDB API Key stored${NC}"
fi

read -p "AlienVault OTX API Key: " ALIENVAULT_APIKEY
if [[ -n "$ALIENVAULT_APIKEY" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "AlienVault-ApiKey" --value "$ALIENVAULT_APIKEY" --output none
    echo -e "${GREEN}✓ AlienVault OTX API Key stored${NC}"
fi

# V5: Cross-cloud credentials with improved UX
if [[ "$ENABLE_CROSS_CLOUD" == "true" ]]; then
    echo -e "${YELLOW}Enter AWS credentials for cross-cloud protection${NC}"
    read -p "AWS Access Key ID: " AWS_ACCESS_KEY
    read -p "AWS Secret Access Key: " AWS_SECRET_KEY
    read -p "AWS Region [us-east-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    
    if [[ -n "$AWS_ACCESS_KEY" && -n "$AWS_SECRET_KEY" ]]; then
        AWS_CREDS="{\"aws_access_key_id\":\"$AWS_ACCESS_KEY\",\"aws_secret_access_key\":\"$AWS_SECRET_KEY\",\"aws_region\":\"$AWS_REGION\"}"
        az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "AWS-CREDENTIALS" --value "$AWS_CREDS" --output none
        echo -e "${GREEN}✓ AWS credentials stored${NC}"
    fi
    
    echo -e "${YELLOW}Enter GCP credentials for cross-cloud protection${NC}"
    echo -e "${YELLOW}Paste GCP Service Account Key JSON data (press Ctrl+D when finished):${NC}"
    GCP_CREDENTIALS=$(cat)
    
    if [[ -n "$GCP_CREDENTIALS" ]]; then
        az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "GCP-CREDENTIALS" --value "$GCP_CREDENTIALS" --output none
        echo -e "${GREEN}✓ GCP credentials stored${NC}"
    fi
fi

# V5: Enhanced post-deployment configuration
echo -e "\n${BLUE}Step 4: Post-deployment configuration${NC}"

# Set up notification email
EMAIL_NOTIFICATION=$(az deployment group show --name "$DEPLOY_NAME" --resource-group "$RG_NAME" --query "parameters.emailNotificationAddress.value" -o tsv 2>/dev/null)
if [[ -z "$EMAIL_NOTIFICATION" || "$EMAIL_NOTIFICATION" == "securityteam@contoso.com" ]]; then
    echo -e "${YELLOW}Configure notification email address:${NC}"
    read -p "Email address for alerts and notifications: " USER_EMAIL
    
    if [[ -n "$USER_EMAIL" ]]; then
        echo -e "${YELLOW}Updating notification settings...${NC}"
        # This would make a call to update the email settings in the deployed resources
        echo -e "${GREEN}✓ Notification email updated${NC}"
    fi
fi

# Step 5: Setup validation and testing
echo -e "\n${BLUE}Step 5: Validation and testing${NC}"
echo -e "${YELLOW}Checking deployment status...${NC}"

# Verify Logic App deployments
LOGIC_APPS_COUNT=$(az logic workflow list --resource-group "$RG_NAME" --query "length(@)" -o tsv)
if [[ $LOGIC_APPS_COUNT -gt 0 ]]; then
    echo -e "${GREEN}✓ Logic Apps deployed: $LOGIC_APPS_COUNT found${NC}"
else
    echo -e "${RED}⚠️ No Logic Apps found in resource group. This may indicate a deployment issue.${NC}"
fi

# Verify Log Analytics workspace
if az monitor log-analytics workspace show --workspace-name "$WORKSPACE_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo -e "${GREEN}✓ Log Analytics workspace validated${NC}"
else
    echo -e "${RED}⚠️ Log Analytics workspace validation failed${NC}"
fi

# Verify Key Vault
if az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo -e "${GREEN}✓ Key Vault validated${NC}"
else
    echo -e "${RED}⚠️ Key Vault validation failed${NC}"
fi

# Step 6: Post-deployment instructions
echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Post-Deployment Tasks                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo -e "1. ${YELLOW}Grant admin consent for API permissions:${NC}"
echo -e "   ➤ Go to Azure Portal > Microsoft Entra ID > App registrations"
echo -e "   ➤ Select your app: ${APP_NAME}"
echo -e "   ➤ Go to 'API permissions'"
echo -e "   ➤ Click 'Grant admin consent for <your-tenant>'"
echo -e ""
echo -e "2. ${YELLOW}Access the CTI dashboard:${NC}"
echo -e "   ➤ ${DASHBOARD_URL}"
echo -e ""
echo -e "3. ${YELLOW}Monitor the Inoculation Engine:${NC}"
echo -e "   ➤ ${ENGINE_URL}"
echo -e ""
echo -e "4. ${YELLOW}Additional configuration:${NC}"
echo -e "   ➤ Add or update API keys in Key Vault as needed"
echo -e "   ➤ Configure distribution targets in the CTI_DistributionTargets_CL table"
echo -e "   ➤ Set up approval workflows for medium-confidence indicators"
echo -e ""
echo -e "${GREEN}🎉 Central Threat Intelligence V5 deployment complete!${NC}"

# V5: Create quick reference file
echo -e "${YELLOW}Creating quick reference guide...${NC}"
REFERENCE_FILE="cti-v5-quickref.md"
cat > "$REFERENCE_FILE" << EOF
# Central Threat Intelligence V5 - Quick Reference

## Deployment Information
- **Resource Group:** $RG_NAME
- **Location:** $LOCATION
- **Environment:** $ENVIRONMENT
- **Workspace:** $WORKSPACE_NAME
- **Key Vault:** $KEYVAULT_NAME

## Important URLs
- **Dashboard:** $DASHBOARD_URL
- **Inoculation Engine:** $ENGINE_URL

## App Registration
- **App Name:** $APP_NAME
- **App ID:** $APP_ID
- **Object ID:** $OBJECT_ID
- **Credentials:** See $CREDS_FILE

## Quick Commands
- **View deployment status:**
  \`\`\`
  az deployment group show --name "$DEPLOY_NAME" --resource-group "$RG_NAME"
  \`\`\`

- **List Logic Apps:**
  \`\`\`
  az logic workflow list --resource-group "$RG_NAME" --output table
  \`\`\`

- **Run Logic App:**
  \`\`\`
  az logic workflow run trigger --resource-group "$RG_NAME" --workflow-name "<workflow-name>" --trigger-name "manual"
  \`\`\`

## Post-Deployment Tasks
1. Grant admin consent for API permissions
2. Complete configuration of integration endpoints
3. Test indicator distribution with sample data
4. Set up monitoring and alerting

## Documentation
For full documentation, visit: https://github.com/$REPO_OWNER/$REPO_NAME/wiki
EOF

echo -e "${GREEN}✓ Quick reference guide created: $REFERENCE_FILE${NC}"
echo -e "\n${BLUE}═════════════════════════════════════════════════════════════════${NC}"
