# Environments

Use the same Terraform and Ansible code across all environments, and change behavior with environment-specific variable files and inventories.

## Terraform

Choose an environment file when planning or applying:

```bash
terraform plan -var-file=environments/dev/terraform.tfvars
terraform apply -var-file=environments/dev/terraform.tfvars
```

Swap `dev` for `uat` or `prod` as needed.

## Ansible

Terraform writes the matching inventory file to:

- `ansible/inventories/dev/hosts.ini`
- `ansible/inventories/uat/hosts.ini`
- `ansible/inventories/prod/hosts.ini`

Run playbooks against the matching inventory:

```bash
cd ansible
ansible-playbook -i inventories/dev/hosts.ini site.yml
```
