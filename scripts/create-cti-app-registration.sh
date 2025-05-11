#!/bin/bash
# CTI App Registration Script - Permissions for the Logic Apps to inoculate the M365 E3 and E5 environment.
set -e

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "\n======================================================="
echo "     CTI Application Registration Setup Script"
echo "======================================================="

echo -e "${BLUE}Checking prerequisites...${NC}"
if ! az account show &> /dev/null; then
  echo -e "${YELLOW}Not logged in to Azure.${NC}"
  az login
fi

# Get subscription and tenant details
SUB_NAME=$(az account show --query name -o tsv)
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo -e "${GREEN}Using subscription: ${SUB_NAME} (${SUB_ID})${NC}"
echo -e "${GREEN}Tenant ID: ${TENANT_ID}${NC}"

# Create app registration
APP_NAME="CTI-Solution"
echo "Creating app registration: ${APP_NAME}..."
APP_CREATE=$(az ad app create --display-name "${APP_NAME}")
APP_ID=$(echo "$APP_CREATE" | jq -r '.appId // .id')
OBJECT_ID=$(echo "$APP_CREATE" | jq -r '.id // .objectId')

if [ -z "$APP_ID" ]; then
  echo -e "${RED}Failed to retrieve Application ID.${NC}"
  exit 1
fi

echo -e "${GREEN}Application successfully created.${NC}"
echo -e "${GREEN}Application (Client) ID: ${APP_ID}${NC}"

echo "Creating service principal for the application..."
az ad sp create --id "$APP_ID" || {
  echo -e "${RED}Failed to create service principal.${NC}"
  exit 1
}
echo -e "${GREEN}Service principal created successfully.${NC}"

# Save credentials to a file
echo "CLIENT_ID=${APP_ID}" > cti-app-credentials.env
echo "APP_OBJECT_ID=${OBJECT_ID}" >> cti-app-credentials.env
echo "APP_NAME=${APP_NAME}" >> cti-app-credentials.env

echo -e "${BLUE}Adding required permissions...${NC}"

# Microsoft Threat Protection API permissions
echo "Adding Microsoft Threat Protection API permissions..."
# resourceAppId: 05a65629-4c1b-48c1-a78b-804c4abdd4af

# AdvancedHunting.Read.All - Run advanced hunting queries
az ad app permission add --id "$APP_ID" \
  --api 05a65629-4c1b-48c1-a78b-804c4abdd4af \
  --api-permissions "a832eaa3-0cfc-4a2b-9af1-27c5b092dd40=Role"

# Alert.ReadWrite.All - Read and write all alerts
az ad app permission add --id "$APP_ID" \
  --api 05a65629-4c1b-48c1-a78b-804c4abdd4af \
  --api-permissions "8e41f311-31d5-43aa-bb79-8fd4e14a8745=Role"

# File.Read.All - Read file profiles
az ad app permission add --id "$APP_ID" \
  --api 05a65629-4c1b-48c1-a78b-804c4abdd4af \
  --api-permissions "cb792285-1541-416c-a581-d8ede4ebc219=Role"

# Url.Read.All - Read URLs
az ad app permission add --id "$APP_ID" \
  --api 05a65629-4c1b-48c1-a78b-804c4abdd4af \
  --api-permissions "e9aa7b67-ea0d-435b-ab36-592cd9b23d61=Role"

# Microsoft Graph API permissions
echo "Adding Microsoft Graph permissions..."
# resourceAppId: 00000003-0000-0000-c000-000000000000

# IdentityRiskEvent.Read.All - Read all identity risk event information
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "6e472fd1-ad78-48da-a0f0-97ab2c6b769e=Role"

# IdentityProvider.Read.All - Read identity providers
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "dc5007c0-2d7d-4c42-879c-2dab87571379=Role"

# Policy.Read.All - Read all your organization's policies
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "01c0a623-fc9b-48e9-b794-0756f8e8f067=Role"

# Policy.ReadWrite.SecurityAction - Read and write Microsoft Entra security action policies
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "2a6baefd-edea-4ff6-b24e-bebcaa27a50d=Role"

# SecurityActions.Read.All - Read your organization's security actions
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "5e0edab9-c148-49d0-b423-ac253e121825=Role"

# SecurityEvents.ReadWrite.All - Read and update your organization's security events
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "d903a879-88e0-4c09-b0c9-82f6a1333f84=Role"

# ServiceHealth.Read.All - Read service health
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "f8f035bb-2cce-47fb-8bf5-7baf3ecbee48=Role"

# ThreatHunting.Read.All - Run hunting queries
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "dd98c7f5-2d42-42d3-a0e4-633161547251=Role"

# ThreatIntelligence.ReadWrite - Read and write threat intelligence information
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "197ee4e9-b993-4066-898f-d6aecc55125b=Role"

# ThreatIndicators.ReadWrite.OwnedBy - Manage threat indicators this app creates or owns
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "21792b6c-c986-4ffc-85de-df9da54b52fa=Role"

# User.Read.All - Read all users' full profiles
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "e0b77adb-e790-44a3-b0a0-257d06303687=Role"

# UserAuthenticationMethod.Read.All - Read all users' authentication methods
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "d72bdbf4-a59b-405c-8b04-5995895819ac=Role"

# SecurityIncident.Read.All - Read all your organization's security incidents
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions "926a6798-b100-4a20-a22f-a4918f13951d=Role"

  # Azure Security Center API permissions
echo "Adding Azure Security Center permissions..."
# resourceAppId: 7b7531ad-5926-4f2d-8a1d-38495ad33e17
az ad app permission add --id "$APP_ID" \
  --api 7b7531ad-5926-4f2d-8a1d-38495ad33e17 \
  --api-permissions "c613cf81-75fb-4201-a32b-7a58d1fe4dff=Role"

# Microsoft Defender for Cloud Apps API permissions
echo "Adding Microsoft Defender for Cloud Apps permissions..."
# resourceAppId: 58c746b0-a0b0-4647-a8f6-12dde5981638
az ad app permission add --id "$APP_ID" \
  --api 58c746b0-a0b0-4647-a8f6-12dde5981638 \
  --api-permissions "179ad82c-ddf7-4180-9ecc-af2608f2ae6d=Role"

az ad app permission add --id "$APP_ID" \
  --api 58c746b0-a0b0-4647-a8f6-12dde5981638 \
  --api-permissions "c05406e2-24d5-4c73-8c33-dde21e8501e6=Role"

az ad app permission add --id "$APP_ID" \
  --api 58c746b0-a0b0-4647-a8f6-12dde5981638 \
  --api-permissions "50974fa0-9c21-4479-a75c-a901ccdb4b5c=Role"

az ad app permission add --id "$APP_ID" \
  --api 58c746b0-a0b0-4647-a8f6-12dde5981638 \
  --api-permissions "2e03c640-95b1-462d-b0cc-811335e6c60b=Role"

# Windows Defender ATP API permissions
echo "Adding Windows Defender ATP permissions..."
# resourceAppId: c98e5057-edde-4666-b301-186a01b4dc58
az ad app permission add --id "$APP_ID" \
  --api c98e5057-edde-4666-b301-186a01b4dc58 \
  --api-permissions "f89ec176-467b-452a-a2eb-7144ac6aa9cc=Role"

# Microsoft Threat Intelligence API permissions
echo "Adding Microsoft Threat Intelligence permissions..."
# resourceAppId: 8ee8fdad-f234-4243-8f3b-15c294843740
az ad app permission add --id "$APP_ID" \
  --api 8ee8fdad-f234-4243-8f3b-15c294843740 \
  --api-permissions "7734e8e5-8dde-42fc-b5ae-6eafea078693=Role"

az ad app permission add --id "$APP_ID" \
  --api 8ee8fdad-f234-4243-8f3b-15c294843740 \
  --api-permissions "8d90f441-09cf-4fdc-ab45-e874fa3a28e8=Role"

az ad app permission add --id "$APP_ID" \
  --api 8ee8fdad-f234-4243-8f3b-15c294843740 \
  --api-permissions "a7deff90-e2f5-4e4e-83a3-2c74e7002e28=Role"

# Microsoft Teams API permissions
echo "Adding Microsoft Teams permissions..."
# resourceAppId: 00000007-0000-0ff1-ce00-000000000000
az ad app permission add --id "$APP_ID" \
  --api 00000007-0000-0ff1-ce00-000000000000 \
  --api-permissions "8f819283-077c-4c68-aa24-0ad706da26e0=Role"

# Microsoft Sentinel API permissions
echo "Adding Microsoft Sentinel permissions..."
# resourceAppId: 9ec59623-ce40-4dc8-a635-ed0275b5d58a
az ad app permission add --id "$APP_ID" \
  --api 9ec59623-ce40-4dc8-a635-ed0275b5d58a \
  --api-permissions "cba40051-8d05-45da-aa85-f6321b023c16=Role"

az ad app permission add --id "$APP_ID" \
  --api 9ec59623-ce40-4dc8-a635-ed0275b5d58a \
  --api-permissions "7e2fc5f2-d647-4926-89f6-f13ad2950560=Role"

az ad app permission add --id "$APP_ID" \
  --api 9ec59623-ce40-4dc8-a635-ed0275b5d58a \
  --api-permissions "04cd5d64-65c5-4dc5-9582-89bac29ed189=Role"

az ad app permission add --id "$APP_ID" \
  --api 9ec59623-ce40-4dc8-a635-ed0275b5d58a \
  --api-permissions "5a55b1b6-8996-4250-abc2-74ec0107ab20=Role"

echo -e "${GREEN}API permissions added successfully.${NC}"

echo -e "${BLUE}Creating client secret...${NC}"
SECRET_YEARS=2
echo "Creating client secret with ${SECRET_YEARS} year(s) duration..."
SECRET_RESULT=$(az ad app credential reset --id "$APP_ID" --years "$SECRET_YEARS" --query password -o tsv)

if [ -z "$SECRET_RESULT" ]; then
  echo -e "${RED}Failed to create client secret.${NC}"
  exit 1
fi

echo "CLIENT_SECRET=${SECRET_RESULT}" >> cti-app-credentials.env
echo -e "${GREEN}Client secret created successfully and saved to cti-app-credentials.env${NC}"
echo -e "${YELLOW}IMPORTANT: Keep this file secure as it contains your client secret!${NC}"

echo -e "\n======================================================="
echo "               Setup Complete!"
echo "======================================================="

echo "App registration has been created successfully with necessary security permissions."
echo -e "\n${YELLOW}IMPORTANT NEXT STEPS:${NC}"
echo "1. Grant admin consent for API permissions in the Azure Portal:"
echo "   - Navigate to: Microsoft Entra ID > App registrations"
echo "   - Select your app: ${APP_NAME}"
echo "   - Go to 'API permissions'"
echo "   - Click 'Grant admin consent for <your-tenant>'"

echo -e "\n2. Run the CTI deployment script with your new client ID:"
echo "   Copy and execute the following command in Azure Cloud Shell to deploy the CTI solution:"
echo "   ----------------------------------------"
echo " SUB_ID=\"\"; PS3='Select subscription: '; mapfile -t SUBS < <(az account list --query \"[].{name:name,id:id}\" -o tsv); select SUB in \"\${SUBS[@]}\"; do [[ -n \$SUB ]] && az account set --subscription \"\${SUB##*$'\t'}\" && echo \"Switched to subscription: \${SUB%%$'\t'*}\" && CHOSEN_SUB_ID=\"\${SUB##*$'\t'}\" && break; done" # Capture chosen ID
echo " curl -sL https://raw.githubusercontent.com/DataGuys/CentralThreatIntelligence/main/deploy.sh | tr -d '\r' |  bash -s -- --client-id ${APP_ID}"
echo "----------------------------------------"

echo -e "\nYour app credentials have been saved to: cti-app-credentials.env"
