#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="CTI-RG"
LOGIC_APPS_FOLDER="logic-apps"
LOCATION="westus2"

echo "[+] Deploying each Logic App in $LOGIC_APPS_FOLDER to resource group $RESOURCE_GROUP..."

for template in "$LOGIC_APPS_FOLDER"/*.json; do
  NAME=$(basename "$template" .json)
  echo "[+] Deploying $NAME..."
  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "logicApp-$NAME-$(date +%Y%m%d%H%M%S)" \
    --template-file "$template" \
    --parameters location="$LOCATION"
done

echo "[✓] Deployment of logic apps complete."