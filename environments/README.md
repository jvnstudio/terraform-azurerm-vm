# Environments

Use the same Terraform and Ansible code across all environments, and change behavior with environment-specific variable files, inventories, and Terraform workspaces.

## Promotion Flow

Promote the same code in this order:
1. Testing (`dev`)
2. UAT (`uat`)
3. Prod (`prod`)

Each environment should use:
- its own Terraform workspace
- its own tfvars file
- its own generated Ansible inventory

## Terraform

Initialize once:

```bash
terraform init
```

For testing (`dev`):

```bash
terraform workspace new dev
terraform workspace select dev
terraform plan -var-file=environments/dev/terraform.tfvars
terraform apply -var-file=environments/dev/terraform.tfvars
```

For UAT:

```bash
terraform workspace new uat
terraform workspace select uat
terraform plan -var-file=environments/uat/terraform.tfvars
terraform apply -var-file=environments/uat/terraform.tfvars
```

For prod:

```bash
terraform workspace new prod
terraform workspace select prod
terraform plan -var-file=environments/prod/terraform.tfvars
terraform apply -var-file=environments/prod/terraform.tfvars
```

If a workspace already exists, just use `terraform workspace select <env>`.

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

Swap `dev` for `uat` or `prod` as needed.

## Important Note

Do not deploy multiple environments into the same Terraform workspace. If you do, Terraform will treat them as one state and try to replace or reuse the wrong resources.
