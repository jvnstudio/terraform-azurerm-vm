# Azure VM Deployment — Terraform + Ansible

## Architecture

```
Internet
    |
    |--- HTTP (port 80) ---> [publicWebapp] Public Web VM (nginx)
    |                              |
    |                         [10.0.1.0/24 subnet]
    |                              |
    |--- Azure Bastion -------> [privateVM] Private VM (no public IP)
         (browser SSH or          |
          native SSH)        [10.0.2.0/26 AzureBastionSubnet]
    |
[cloudforce-vnet 10.0.0.0/16]
```

**Two VMs:**
- `privateVM` — Private Linux VM, no public IP, accessible only through Azure Bastion
- `publicWebapp` — Public Linux VM running nginx, accessible from the internet on port 80

**Tools:**
- **Terraform** provisions infrastructure (VMs, networking, Bastion)
- **Ansible** configures VMs (installs packages, deploys web app)

---

## Prerequisites

1. **Azure CLI** — logged in with an active subscription
   ```bash
   az login
   az account show
   ```

2. **Terraform** >= 1.0
   ```bash
   terraform --version
   ```

3. **Ansible**
   ```bash
   pip3 install ansible
   ```

4. **SSH key pair** (RSA, required by Azure)
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_rsa -N ""
   ```

---

## Step 1: Choose an Environment

Use the environment-specific tfvars files in `environments/`.

In this repo:
- `testing` maps to `dev`
- `uat` maps to `uat`
- `prod` maps to `prod`

Use a separate Terraform workspace for each environment so the state does not overlap.

| Stage | Workspace | tfvars file | Resource group | Ansible inventory |
|---|---|---|---|---|
| Testing | `dev` | `environments/dev/terraform.tfvars` | `terraform-compute-dev` | `ansible/inventories/dev/hosts.ini` |
| UAT | `uat` | `environments/uat/terraform.tfvars` | `terraform-compute-uat` | `ansible/inventories/uat/hosts.ini` |
| Prod | `prod` | `environments/prod/terraform.tfvars` | `terraform-compute-prod` | `ansible/inventories/prod/hosts.ini` |

Example `environments/dev/terraform.tfvars`:

```hcl
environment          = "dev"
location             = "westus"
resource_group_name  = "terraform-compute-dev"
vm_hostname          = "myvmdev"           # Prefix for shared Azure resources
private_vm_name      = "privateVM"
public_web_vm_name   = "publicWebapp"
vm_os_simple         = "UbuntuServer"
vm_size              = "Standard_D2s_v3"
nb_instances         = 1
admin_username       = "azureuser"
ssh_key              = "~/.ssh/azure_rsa.pub"
nb_public_ip         = 0
public_ip_dns        = [""]
enable_bastion       = true
enable_public_web_vm = true
admin_source_ip      = null                 # Auto-detect your current public IP for SSH
```

If you want to override auto-detect without committing your IP, create a local file such as `personal.local.auto.tfvars`:
```hcl
admin_source_ip = "73.134.101.146/32"
```

---

## Step 2: Initialize Terraform Once

```bash
cd /path/to/terraform-azurerm-vm
terraform init
```

---

## Step 3: Spin Up Testing First

If this is the first time creating the testing workspace:
```bash
terraform workspace new dev
```

Then select it and deploy:
```bash
cd /path/to/terraform-azurerm-vm
terraform workspace select dev
terraform plan -var-file=environments/dev/terraform.tfvars
terraform apply -var-file=environments/dev/terraform.tfvars
```

Configure testing with Ansible:
```bash
cd ansible
ansible-playbook -i inventories/dev/hosts.ini site.yml --limit webservers
```

Verify testing before promoting the same code to the next stage.

---

## Step 4: Promote to UAT

If this is the first time creating the UAT workspace:
```bash
terraform workspace new uat
```

Then select it and deploy:
```bash
cd /path/to/terraform-azurerm-vm
terraform workspace select uat
terraform plan -var-file=environments/uat/terraform.tfvars
terraform apply -var-file=environments/uat/terraform.tfvars
```

Configure UAT with Ansible:
```bash
cd ansible
ansible-playbook -i inventories/uat/hosts.ini site.yml --limit webservers
```

---

## Step 5: Promote to Prod

If this is the first time creating the prod workspace:
```bash
terraform workspace new prod
```

Then select it and deploy:
```bash
cd /path/to/terraform-azurerm-vm
terraform workspace select prod
terraform plan -var-file=environments/prod/terraform.tfvars
terraform apply -var-file=environments/prod/terraform.tfvars
```

Configure prod with Ansible:
```bash
cd ansible
ansible-playbook -i inventories/prod/hosts.ini site.yml --limit webservers
```

---

## Step 6: What Gets Created

| Resource | Count | Purpose |
|---|---|---|
| Resource Group | 1 | Container for all resources |
| Virtual Network | 1 | 10.0.0.0/16 |
| VM Subnet | 1 | 10.0.1.0/24 |
| Bastion Subnet | 1 | 10.0.2.0/26 (AzureBastionSubnet) |
| NSG (private) | 1 | SSH from VNet only |
| NSG (web) | 1 | HTTP/HTTPS from anywhere, SSH from your IP |
| Bastion Public IP | 1 | Standard/Static |
| Bastion Host | 1 | Standard SKU with tunneling |
| Web Public IP | 1 | Standard/Static |
| NICs | 2 | One per VM |
| Availability Set | 1 | For the private VM |
| Private Linux VM | 1 | privateVM |
| Public Web VM | 1 | publicWebapp |
| Ansible Inventory | 1 | Auto-generated at `ansible/inventories/<env>/hosts.ini` |

**Note:** Bastion can take 5-10 minutes to provision. The web page will not work until Ansible has run.

---

## Step 7: Verify

### Check the web app
```bash
terraform output web_vm_url
curl http://$(terraform output -raw web_vm_public_ip)
```

### SSH to the private VM in testing via Bastion
```bash
terraform workspace select dev
az network bastion ssh \
  --name myvmdev-bastion \
  --resource-group terraform-compute-dev \
  --target-resource-id $(terraform output -json vm_ids | jq -r '.[0]') \
  --auth-type ssh-key \
  --username azureuser \
  --ssh-key ~/.ssh/azure_rsa
```

For UAT or prod, select the matching workspace and swap the resource group and Bastion name:
- UAT: `terraform workspace select uat`, `terraform-compute-uat`, `myvmuat-bastion`
- Prod: `terraform workspace select prod`, `terraform-compute-prod`, `myvmprod-bastion`

### SSH to the private VM via Azure Portal
1. Go to Azure Portal > Virtual Machines > `privateVM`
2. Click **Connect** > **Bastion**
3. Username: `azureuser`
4. Authentication Type: **SSH Private Key from Local File**
5. Browse to `~/.ssh/azure_rsa`
6. Click **Connect**

### SSH to the web VM directly
```bash
ssh -i ~/.ssh/azure_rsa azureuser@$(terraform output -raw web_vm_public_ip)
```

---

## Updating Configuration with Ansible

The key benefit of Ansible: change VM config without reprovisioning.

### Update the web page
Edit `ansible/templates/index.html.j2`, then:
```bash
cd ansible
ansible-playbook -i inventories/<env>/hosts.ini playbooks/webserver.yml
```

### Install new packages on all VMs
Edit `ansible/playbooks/base.yml`, add packages to the list, then:
```bash
cd ansible
ansible-playbook -i inventories/<env>/hosts.ini playbooks/base.yml
```

### Run a one-off command on all reachable VMs
```bash
cd ansible
ansible -i inventories/<env>/hosts.ini webservers -m shell -a "uptime"
```

### Run everything
```bash
cd ansible
ansible-playbook -i inventories/<env>/hosts.ini site.yml
```

---

## File Structure

```
terraform-azurerm-vm/
  main.tf                  # All infrastructure resources
  variables.tf             # Variable declarations
  outputs.tf               # Output values
  terraform.tfvars         # Optional single-environment local overrides
  environments/
    dev/
      terraform.tfvars
    uat/
      terraform.tfvars
    prod/
      terraform.tfvars
  os/
    variables.tf           # OS image mappings
    outputs.tf             # OS image lookup logic
  ansible/
    ansible.cfg            # Ansible connection settings
    inventory.tpl          # Inventory template (Terraform populates)
    inventories/
      dev/
        hosts.ini          # Generated inventory (don't edit)
      uat/
        hosts.ini
      prod/
        hosts.ini
    site.yml               # Master playbook (runs all)
    playbooks/
      base.yml             # Common config for all VMs
      webserver.yml        # Nginx + web app for public VM
    templates/
      index.html.j2        # Web app landing page (Jinja2)
```

---

## Tear Down

Destroy one environment at a time:
```bash
terraform workspace select dev
terraform destroy -var-file=environments/dev/terraform.tfvars
```

Swap `dev` for `uat` or `prod` as needed.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Wrong environment targeted | Check `terraform workspace show` and make sure it matches the tfvars file you are using |
| SSH timeout to web VM | Leave `admin_source_ip = null` for auto-detect, or if you set it manually make sure it matches your current public IP/CIDR |
| Bastion won't connect | Bastion takes 5-10 min to provision. Check that it is in `Succeeded` state in the Azure portal |
| Ansible `UNREACHABLE` | Make sure Terraform finished, the VM completed boot, and you are using the matching `ansible/inventories/<env>/hosts.ini` file |
