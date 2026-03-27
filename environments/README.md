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

## Remote State Backend

Terraform state is stored in Azure Storage so it's shared between local dev and Jenkins.

**First-time setup** (run once):
```bash
./bootstrap-backend.sh
```

This creates:
- Resource group: `terraform-state-rg`
- Storage account: `tfstatecloudforce`
- Blob container: `tfstate`

Then initialize with the storage key:
```bash
export ARM_ACCESS_KEY="<key from bootstrap output>"
terraform init
```

Or use a backend config file:
```bash
echo 'access_key = "<key>"' > backend.hcl
terraform init -backend-config=backend.hcl
```

For Jenkins, store the key as credential `azure-tf-state-access-key`.

## Terraform

Initialize once (after backend setup):

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

## Jenkins

A sample declarative pipeline is provided in `Jenkinsfile`.

The pipeline:
- validates Terraform
- deploys `dev`, then `uat`, then `prod`
- pauses for manual approval before `prod`
- runs Ansible against the matching generated inventory for each environment

Useful Jenkins job parameters:
- `PROMOTE_TO`: choose the highest environment to deploy in that run
- `RUN_ANSIBLE`: toggle post-Terraform configuration with Ansible

Expected Jenkins credentials:
- `azure-arm-client-id` as Secret Text
- `azure-arm-client-secret` as Secret Text
- `azure-arm-subscription-id` as Secret Text
- `azure-arm-tenant-id` as Secret Text
- `azure-tf-state-access-key` as Secret Text (storage account key from `bootstrap-backend.sh`)
- `azure-vm-ssh-key` as SSH Username with private key

Expected Jenkins agent tools:
- Terraform
- Azure CLI
- Ansible
- OpenSSH tools including `ssh-keygen`

### Create The Pipeline Job In Jenkins UI

1. In Jenkins, click **New Item**.
2. Enter a job name such as `terraform-azurerm-vm-pipeline`.
3. Select **Pipeline** and click **OK**.
4. In **General**, optionally check **This project is parameterized** if you want Jenkins to expose the parameters early, although the `Jenkinsfile` already defines them.
5. In **Pipeline**, set **Definition** to **Pipeline script from SCM**.
6. Set **SCM** to **Git**.
7. Enter your repo URL, for example `https://github.com/jvnstudio/terraform-azurerm-vm.git`.
8. Add Jenkins Git credentials if the repo is private.
9. Set **Branches to build** to `*/master`.
10. Set **Script Path** to `Jenkinsfile`.
11. Click **Save**.
12. Click **Build with Parameters** and choose:
    - `PROMOTE_TO=dev` to deploy testing only
    - `PROMOTE_TO=uat` to deploy dev then uat
    - `PROMOTE_TO=prod` to deploy dev then uat then prod
    - `RUN_ANSIBLE=true` to apply the Ansible configuration after Terraform

### First Run Checklist

Before the first Jenkins run, make sure:
- the Jenkins agent can run `terraform`, `az`, `ansible`, and `ssh-keygen`
- the Azure service principal has permission to create and manage resources in the target subscription
- the `azure-vm-ssh-key` credential contains the private key that matches the public key path used by Terraform
- the Jenkins job can reach Azure and the provisioned VMs over the required network paths
- manual approval for prod is allowed for the users who will operate this pipeline

