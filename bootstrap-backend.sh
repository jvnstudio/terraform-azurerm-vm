#!/bin/bash
# Bootstrap the Azure Storage backend for Terraform remote state.
# Run this ONCE before the first 'terraform init'.
#
# Usage: ./bootstrap-backend.sh
#
# Prerequisites: az login

set -euo pipefail

RESOURCE_GROUP="terraform-state-rg"
LOCATION="westus"
STORAGE_ACCOUNT="tfstatecloudforce"
CONTAINER="tfstate"

echo "==> Creating resource group: $RESOURCE_GROUP"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none

echo "==> Creating storage account: $STORAGE_ACCOUNT"
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output none

echo "==> Creating blob container: $CONTAINER"
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login \
  --output none

echo "==> Fetching storage account key..."
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT" \
  --query '[0].value' \
  --output tsv)

echo ""
echo "Backend is ready. To initialize Terraform, run:"
echo ""
echo "  export ARM_ACCESS_KEY=\"$ACCOUNT_KEY\""
echo "  terraform init -migrate-state"
echo ""
echo "Or save the key in backend.hcl:"
echo ""
echo "  echo 'access_key = \"$ACCOUNT_KEY\"' > backend.hcl"
echo "  terraform init -backend-config=backend.hcl -migrate-state"
echo ""
echo "For Jenkins, store the access key as a 'Secret Text' credential"
echo "named 'azure-tf-state-access-key' and pass it as ARM_ACCESS_KEY."
