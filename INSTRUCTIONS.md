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
   # Generate if you don't already have one
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_rsa -N ""
   ```

---

## Step 1: Review Configuration

Edit `terraform.tfvars` to match your environment:

```hcl
location             = "westus"
resource_group_name  = "terraform-compute"
vm_hostname          = "myvm"              # Prefix for shared Azure resources
private_vm_name      = "privateVM"
public_web_vm_name   = "publicWebapp"
vm_os_simple         = "UbuntuServer"
vm_size              = "Standard_D2s_v3"
nb_instances         = 1
admin_username       = "azureuser"
ssh_key              = "~/.ssh/azure_rsa.pub"
nb_public_ip         = 0                    # Private VM has no public IP
public_ip_dns        = [""]
enable_bastion       = true                 # Creates Azure Bastion jumpbox
enable_public_web_vm = true                 # Creates public web VM
admin_source_ip      = "YOUR_PUBLIC_IP"     # Lock SSH to your IP
```

To find your public IP:
```bash
curl -s ifconfig.me
```

---

## Step 2: Provision Infrastructure with Terraform

```bash
cd /path/to/terraform-azurerm-vm

# Initialize providers
terraform init

# Preview what will be created
terraform plan

# Apply — creates all resources
terraform apply
```

**What gets created:**
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
| Ansible Inventory | 1 | Auto-generated at ansible/inventories/<env>/hosts.ini |

**Note:** Bastion takes ~5-10 minutes to provision. The web page will NOT work yet — Ansible hasn't run.

---

## Step 3: Configure VMs with Ansible

```bash
cd ansible

# Run all playbooks (base config + web server)
ansible-playbook -i inventories/dev/hosts.ini site.yml --limit webservers
```

This runs two playbooks in sequence:

### base.yml (all VMs)
- Updates apt cache
- Installs common packages (curl, wget, vim, htop, unzip, net-tools)
- Sets timezone to UTC
- Enables UFW firewall with default deny
- Allows SSH through firewall

### webserver.yml (webservers group only)
- Installs nginx
- Opens HTTP (80) and HTTPS (443) in UFW
- Deploys the landing page from `templates/index.html.j2`
- Starts and enables nginx

---

## Step 4: Verify

### Check the web app
```bash
# Get the public IP
terraform output web_vm_url

# Open in browser or curl
curl http://$(terraform output -raw web_vm_public_ip)
```

You should see a styled "Hello from Azure!" page with live system info.

### SSH to the private VM via Bastion (native client)
```bash
az network bastion ssh \
  --name myvm-bastion \
  --resource-group terraform-compute \
  --target-resource-id $(terraform output -json vm_ids | jq -r '.[0]') \
  --auth-type ssh-key \
  --username azureuser \
  --ssh-key ~/.ssh/azure_rsa
```

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
ansible-playbook -i inventories/dev/hosts.ini playbooks/webserver.yml
```

### Install new packages on all VMs
Edit `ansible/playbooks/base.yml`, add packages to the list, then:
```bash
cd ansible
ansible-playbook -i inventories/dev/hosts.ini playbooks/base.yml
```

### Run a one-off command on all reachable VMs
```bash
cd ansible
ansible -i inventories/dev/hosts.ini webservers -m shell -a "uptime"
```

### Run everything
```bash
cd ansible
ansible-playbook -i inventories/dev/hosts.ini site.yml
```

---

## File Structure

```
terraform-azurerm-vm/
  main.tf                  # All infrastructure resources
  variables.tf             # Variable declarations
  outputs.tf               # Output values
  terraform.tfvars         # Your configuration values
  os/
    variables.tf           # OS image mappings
    outputs.tf             # OS image lookup logic
  ansible/
    ansible.cfg            # Ansible connection settings
    inventory.tpl          # Inventory template (Terraform populates)
    inventories/
      dev/
        hosts.ini        # Generated inventory (don't edit)
    site.yml               # Master playbook (runs all)
    playbooks/
      base.yml             # Common config for all VMs
      webserver.yml         # Nginx + web app for public VM
    templates/
      index.html.j2        # Web app landing page (Jinja2)
    roles/                 # For future role-based organization
```

---

## Tear Down

To destroy all resources:
```bash
terraform destroy
```

This removes everything from Azure. The Ansible files and Terraform config remain locally.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `SkuNotAvailable` | Run `az vm list-skus --location westus --output table` and pick an available size |
| SSH timeout to web VM | Check `admin_source_ip` in tfvars matches your current public IP (`curl ifconfig.me`) |
| Bastion won't connect | Bastion takes 5-10 min to provision. Check it's in "Succeeded" state in the portal |
| Ansible `UNREACHABLE` | Ensure NSG allows SSH from your IP and the VM has finished booting |
| Web page blank | Run `ansible-playbook playbooks/webserver.yml` — nginx isn't installed until Ansible runs |
| `command not found: ansible-playbook` | Run `pip3 install ansible` |
