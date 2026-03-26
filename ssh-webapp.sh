#!/bin/bash
# SSH into the publicWebapp VM
# Usage: ./ssh-webapp.sh

set -e

SSH_KEY="$HOME/.ssh/azure_rsa"
USERNAME="azureuser"

# Get the public IP from Terraform output
WEB_IP=$(terraform output -raw web_vm_public_ip 2>/dev/null)

if [ -z "$WEB_IP" ]; then
  echo "Error: Could not get web_vm_public_ip from Terraform output."
  echo "Make sure you have run 'terraform apply' and are in the correct workspace."
  exit 1
fi

echo "Connecting to publicWebapp at $WEB_IP..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USERNAME@$WEB_IP"
