#!/bin/bash
# Script to automatically purge all soft-deleted Azure Key Vaults

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   Azure Key Vault Cleanup Utility${NC}"
echo -e "${BLUE}==================================================${NC}"

# Check for Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed.${NC}"
    echo "Please install Azure CLI first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}You are not logged in to Azure. Initiating login...${NC}"
    az login
fi

# Get current subscription
SUB_NAME=$(az account show --query name -o tsv)
SUB_ID=$(az account show --query id -o tsv)
echo -e "${BLUE}Current subscription: ${GREEN}${SUB_NAME} (${SUB_ID})${NC}"

echo -e "\n${BLUE}Retrieving and purging all soft-deleted Key Vaults...${NC}"

# First try - attempt to get a list and purge all vaults
echo -e "${YELLOW}Approach 1: Getting list of deleted vaults...${NC}"
DELETED_VAULTS=$(az keyvault list-deleted --query "[].name" -o tsv 2>/dev/null)

if [ $? -eq 0 ] && [ ! -z "$DELETED_VAULTS" ]; then
    COUNT=$(echo "$DELETED_VAULTS" | wc -l)
    echo -e "${GREEN}Found ${COUNT} soft-deleted Key Vault(s).${NC}"
    
    for vault in $DELETED_VAULTS; do
        echo -e "${YELLOW}Purging Key Vault: ${vault}${NC}"
        az keyvault purge --name "$vault" --no-wait
        echo -e "${GREEN}Purge command sent for: ${vault}${NC}"
    done
    
    echo -e "${GREEN}All purge commands have been sent. Vaults will be purged in the background.${NC}"
else
    echo -e "${YELLOW}No vaults found or failed to retrieve list.${NC}"
    
    # Second approach - try common CTI vault names
    echo -e "${YELLOW}Approach 2: Trying to purge common CTI vault names...${NC}"
    COMMON_VAULTS=("ctikvprod" "ctikvdev" "ctikvtest")
    
    for vault in "${COMMON_VAULTS[@]}"; do
        echo -e "${YELLOW}Attempting to purge Key Vault: ${vault}${NC}"
        az keyvault purge --name "$vault" --no-wait
        echo -e "${GREEN}Purge command sent for: ${vault} (regardless of existence)${NC}"
    done
    
    # Third approach - try the specific vault name that's causing issues
    echo -e "${YELLOW}Approach 3: Enter the specific vault name causing the 'VaultAlreadyExists' error:${NC}"
    read -p "Vault name: " specific_vault
    
    if [ ! -z "$specific_vault" ]; then
        echo -e "${YELLOW}Attempting to purge Key Vault: ${specific_vault}${NC}"
        az keyvault purge --name "$specific_vault" --no-wait
        echo -e "${GREEN}Purge command sent for: ${specific_vault}${NC}"
    fi
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}Purge process completed.${NC}"
echo -e "${YELLOW}Note: Actual purging may take several minutes to complete in Azure.${NC}"
echo -e "${BLUE}==================================================${NC}"
