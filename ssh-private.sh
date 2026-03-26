#!/bin/bash
# SSH into the privateVM via Azure Bastion
# Usage: ./ssh-private.sh

set -e

SSH_KEY="$HOME/.ssh/azure_rsa"
USERNAME="azureuser"

# Get values from Terraform output
VM_ID=$(terraform output -json vm_ids 2>/dev/null | jq -r '.[0]')
BASTION_NAME=$(terraform output -raw bastion_name 2>/dev/null)
RG=$(terraform output -raw 2>/dev/null <<< "" || true)

if [ -z "$VM_ID" ] || [ "$VM_ID" = "null" ]; then
  echo "Error: Could not get vm_ids from Terraform output."
  echo "Make sure you have run 'terraform apply' and are in the correct workspace."
  exit 1
fi

# Extract resource group from the VM ID
RG=$(echo "$VM_ID" | sed 's|.*resourceGroups/||' | cut -d'/' -f1)

echo "Connecting to privateVM via Bastion ($BASTION_NAME)..."
az network bastion ssh \
  --name "$BASTION_NAME" \
  --resource-group "$RG" \
  --target-resource-id "$VM_ID" \
  --auth-type ssh-key \
  --username "$USERNAME" \
  --ssh-key "$SSH_KEY"
