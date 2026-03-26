#!/usr/bin/env bash
# From your Mac terminal, not from inside myvm0
az network bastion ssh \
  --name myvm-bastion \
  --resource-group terraform-compute \
  --target-resource-id $(terraform output -json vm_ids | jq -r '.[0]') \
  --auth-type ssh-key \
  --username azureuser \
  --ssh-key ~/.ssh/azure_rsa
