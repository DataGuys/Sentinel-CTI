#!/usr/bin/env bash
#set -euo pipefail

################################################################################
# Central Threat Intelligence – unattended deploy script
# Usage (one‑liner):
#   curl -sL https://raw.githubusercontent.com/DataGuys/CentralThreatIntelligenceV2/main/deploy.sh | \
#     bash -s -- -p myprefix -e dev -t Basic -l eastus -s <sub‑id>
################################################################################

REPO_BRANCH="${REPO_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/DataGuys/CentralThreatIntelligenceV2/${REPO_BRANCH}"
DEPLOY_NAME="cti-$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<EOF
Usage: deploy.sh [-l location] [-p prefix] [-e environment] [-t table_plan] [-s subscription]
  -l  Azure region                    (default: first 'Recommended' region or westus2)
  -p  Resource name prefix            (default: cti)
  -e  Environment tag                 (default: prod)
  -t  Table plan: Analytics|Basic|Aux (default: Analytics)
  -s  Azure subscription ID or name   (default: current az context)
  -h  Help
EOF
  exit 1
}

#------------------ Defaults ----------------------------------------------------
LOCATION=""
PREFIX="cti"
ENVIRONMENT="prod"
TABLE_PLAN="Analytics"
SUBSCRIPTION=""

#------------------ Parse CLI args ---------------------------------------------
while getopts "l:p:e:t:s:h" opt; do
  case "$opt" in
    l) LOCATION="$OPTARG" ;;
    p) PREFIX="$OPTARG" ;;
    e) ENVIRONMENT="$OPTARG" ;;
    t) TABLE_PLAN="$OPTARG" ;;
    s) SUBSCRIPTION="$OPTARG" ;;
    h|*) usage ;;
  esac
done

#------------------ Prerequisites ----------------------------------------------
command -v az >/dev/null   || { echo "❌ Azure CLI not found"; exit 1; }
command -v jq >/dev/null   || { echo "❌ 'jq' is required";    exit 1; }

#------------------ Azure login / subscription ---------------------------------
if ! az account show &>/dev/null; then
  echo "[+] Logging in to Azure CLI…"
  az login --only-show-errors
fi

if [[ -z "$SUBSCRIPTION" ]]; then
  # If running in an interactive TTY, offer a choice; otherwise keep current.
  if [[ -t 0 ]]; then
    echo "[+] Choose a subscription (Enter to keep current):"
    mapfile -t SUBS < <(az account list --query "[].{name:name,id:id}" -o tsv)
    select SUB in "${SUBS[@]}"; do
      [[ -n "$SUB" ]] && SUBSCRIPTION="${SUB##*$'\t'}" && break || break
    done
  fi
fi

[[ -n "$SUBSCRIPTION" ]] && az account set --subscription "$SUBSCRIPTION"

#------------------ Resolve default location -----------------------------------
if [[ -z "$LOCATION" ]]; then
  LOCATION="$(az account list-locations \
               --query "[?metadata.regionCategory=='Recommended'].name | [0]" \
               -o tsv 2>/dev/null || echo westus2)"
fi

#------------------ Validate table plan ----------------------------------------
case "${TABLE_PLAN,,}" in
  analytics|basic|auxiliary) TABLE_PLAN="$(tr '[:lower:]' '[:upper:]' <<< "$TABLE_PLAN")" ;;
  *) echo "❌ Invalid table plan. Use Analytics | Basic | Auxiliary"; exit 1 ;;
esac

echo "──────────────── Deploying CTI ────────────────"
echo " Subscription : $(az account show --query name -o tsv)"
echo " Location     : $LOCATION"
echo " Prefix       : $PREFIX"
echo " Environment  : $ENVIRONMENT"
echo " Table plan   : $TABLE_PLAN"
echo " Deployment   : $DEPLOY_NAME"
echo "───────────────────────────────────────────────"

#------------------ Core deployment --------------------------------------------
az deployment sub create \
  --name "$DEPLOY_NAME" \
  --location "$LOCATION" \
  --template-file "./main.bicep" \
  --parameters prefix="$PREFIX" environment="$ENVIRONMENT" location="$LOCATION"

#------------------ Outputs -----------------------------------------------------
OUTPUTS=$(az deployment sub show --name "$DEPLOY_NAME" \
           --query "properties.outputs" -o json)

WORKSPACE_NAME=$(jq -r '.workspaceName.value'     <<< "$OUTPUTS")
RESOURCE_GROUP=$(jq -r '.resourceGroupName.value' <<< "$OUTPUTS")

#------------------ Custom tables ----------------------------------------------
echo "[+] Creating custom Log Analytics tables in '$WORKSPACE_NAME'…"

TEMP_JSON="./tables/custom-tables.json"

jq -c '.[]' "$TEMP_JSON" | while read -r tbl; do
  TBL_NAME=$(jq -r '.name'    <<< "$tbl")
  COLS    =$(jq -c '.columns' <<< "$tbl")
  printf '  • %-40s\r' "$TBL_NAME"

  # Create if missing (ignore 409 errors)
  az monitor log-analytics workspace table create \
      --resource-group "$RESOURCE_GROUP" \
      --workspace-name "$WORKSPACE_NAME" \
      --name           "$TBL_NAME" \
      --columns        "$COLS" \
      --retention-time 30 \
      --only-show-errors >/dev/null || true

  # Ensure plan matches requested tier
  az monitor log-analytics workspace table update \
      --resource-group "$RESOURCE_GROUP" \
      --workspace-name "$WORKSPACE_NAME" \
      --name  "$TBL_NAME" \
      --plan  "$TABLE_PLAN" \
      --only-show-errors >/dev/null
done
echo

echo "🎉  Deployment complete – tables set to '$TABLE_PLAN'."
