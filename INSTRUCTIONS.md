# CloudForce — Azure + Ansible Infrastructure Demo

## Architecture

```
                        Internet
                           |
                           | HTTP/HTTPS (ports 80, 443)
                           v
                   +----------------+
                   | publicWebapp   |  <-- Public Web VM (nginx)
                   | Public IP      |      SSH from your admin IP
                   | 10.0.3.0/24   |      SSH from private subnet
                   +----------------+
                           |
    cloudforce-vnet (10.0.0.0/16)
                           |
         +-----------------+-----------------+
         |                                   |
+------------------+              +--------------------+
| myvm-web-subnet  |              | myvm-subnet        |
| 10.0.3.0/24      |              | 10.0.1.0/24        |
| publicWebapp     |              | privateVM          |
+------------------+              +--------------------+
                                         |
                              SSH (private only)
                                         |
                              +--------------------+
                              | AzureBastionSubnet |
                              | 10.0.2.0/26        |
                              | myvm-bastion       |
                              +--------------------+
                                         |
                                    Azure Bastion
                                   (portal or CLI)
                                         |
                                     Your Mac

         +--------------------+
         | NAT Gateway        |  <-- Outbound internet for privateVM
         | myvm-natgw         |      (apt-get, curl, etc.)
         +--------------------+
```

**Two VMs:**
- `privateVM` — Private Linux VM in its own subnet, no public IP, accessible only through Azure Bastion
- `publicWebapp` — Public Linux VM in a separate web subnet, running nginx, accessible from the internet on port 80/443

**Private-to-public path:**
- `privateVM` connects to `publicWebapp` over the VNet using its **private IP** (10.0.3.x), never the public IP
- The web NSG explicitly allows SSH from the private subnet (10.0.1.0/24)

**Tools:**
- **Terraform** provisions infrastructure (VMs, networking, Bastion, NAT Gateway)
- **Ansible** configures VMs (installs packages, deploys web app)

---

## Network Segmentation

| Subnet | CIDR | Contains | Inbound rules |
|---|---|---|---|
| `myvm-subnet` | 10.0.1.0/24 | privateVM | SSH from Bastion subnet only; deny all else |
| `myvm-web-subnet` | 10.0.3.0/24 | publicWebapp | HTTP/HTTPS from internet; SSH from admin IP; SSH from private subnet |
| `AzureBastionSubnet` | 10.0.2.0/26 | Bastion host | Managed by Azure |

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

## Step 1: Choose an Environment

Use the environment-specific tfvars files in `environments/`.

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
vm_hostname          = "myvmdev"
private_vm_name      = "privateVM"
public_web_vm_name   = "publicWebapp"
vm_os_simple         = "UbuntuServer"
vm_size              = "Standard_D2s_v3"
nb_instances         = 1
admin_username       = "azureuser"
ssh_key              = "~/.ssh/azure_rsa.pub"
nb_public_ip         = 0
public_ip_dns        = [""]
enable_nat_gateway   = true
enable_bastion       = true
enable_public_web_vm = true
admin_source_ip      = null                 # Auto-detect your current public IP
```

---

## Step 2: Provision Infrastructure

```bash
cd /path/to/terraform-azurerm-vm

# Initialize providers (first time only)
terraform init

# Create/select workspace
terraform workspace new dev    # first time
terraform workspace select dev # subsequent times

# Preview and apply
terraform plan  -var-file=environments/dev/terraform.tfvars
terraform apply -var-file=environments/dev/terraform.tfvars
```

**What gets created:**

| Resource | Count | Purpose |
|---|---|---|
| Resource Group | 1 | Container for all resources |
| Virtual Network | 1 | cloudforce-vnet (10.0.0.0/16) |
| Private Subnet | 1 | 10.0.1.0/24 — privateVM |
| Bastion Subnet | 1 | 10.0.2.0/26 — AzureBastionSubnet |
| Web Subnet | 1 | 10.0.3.0/24 — publicWebapp |
| NSG (private) | 1 | SSH from Bastion only, deny all else inbound |
| NSG (web) | 1 | HTTP/HTTPS from internet, SSH from admin IP + private subnet |
| NAT Gateway + PIP | 2 | Outbound internet for privateVM |
| Bastion Host + PIP | 2 | Standard SKU with native tunneling |
| Web Public IP | 1 | Standard/Static — internet-facing |
| NICs | 2 | One per VM, in separate subnets |
| Availability Set | 1 | For the private VM |
| Private Linux VM | 1 | privateVM (no public IP) |
| Public Web VM | 1 | publicWebapp (public IP) |
| Ansible Inventory | 1 | Auto-generated at `ansible/inventories/<env>/hosts.ini` |

**Note:** Bastion takes 5-10 minutes to provision. The web page will not work until Ansible runs.

---

## Step 3: Configure VMs with Ansible

```bash
cd ansible

# Configure the web server
ansible-playbook -i inventories/dev/hosts.ini site.yml --limit webservers
```

This runs two playbooks:

### base.yml (all VMs)
- Updates apt cache
- Installs common packages (curl, wget, vim, htop, unzip, net-tools)
- Sets timezone to UTC
- Enables UFW firewall with default deny
- Allows SSH through firewall

### webserver.yml (webservers group only)
- Installs nginx
- Opens HTTP (80) and HTTPS (443) in UFW
- Deploys the CloudForce landing page from `templates/index.html.j2`
- Starts and enables nginx

---

## Step 4: Verify

### Check the web app (external access)
```bash
terraform output web_vm_url
curl http://$(terraform output -raw web_vm_public_ip)
```

You should see the CloudForce demo page.

### SSH to privateVM via Bastion (native client)
```bash
az network bastion ssh \
  --name myvmdev-bastion \
  --resource-group terraform-compute-dev \
  --target-resource-id $(terraform output -json vm_ids | jq -r '.[0]') \
  --auth-type ssh-key \
  --username azureuser \
  --ssh-key ~/.ssh/azure_rsa
```

### SSH to privateVM via Azure Portal
1. Go to Azure Portal > Virtual Machines > `privateVM`
2. Click **Connect** > **Bastion**
3. Username: `azureuser`
4. Auth Type: **SSH Private Key from Local File**
5. Browse to `~/.ssh/azure_rsa`
6. Click **Connect**

### Connect from privateVM to publicWebapp (private path)
Once on privateVM via Bastion:
```bash
# Check the web app internally (uses private IP, stays within VNet)
curl http://$(cat /etc/ansible/facts.d/web_vm_private_ip 2>/dev/null || echo "10.0.3.4")

# Or SSH to publicWebapp over the private network
ssh azureuser@<web_vm_private_ip>
```

Get the private IP from Terraform:
```bash
terraform output web_vm_private_ip
```

### SSH to publicWebapp directly from your Mac
```bash
ssh -i ~/.ssh/azure_rsa azureuser@$(terraform output -raw web_vm_public_ip)
```

---

## Updating Configuration with Ansible

Change VM config without reprovisioning.

### Update the web page
Edit `ansible/templates/index.html.j2`, then:
```bash
cd ansible
ansible-playbook -i inventories/<env>/hosts.ini playbooks/webserver.yml
```

### Install new packages on all VMs
Edit `ansible/playbooks/base.yml`, add packages, then:
```bash
cd ansible
ansible-playbook -i inventories/<env>/hosts.ini playbooks/base.yml
```

### Run a one-off command
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
  locals.tf                # Computed values (VM names, tags, paths)
  environments/
    dev/terraform.tfvars
    uat/terraform.tfvars
    prod/terraform.tfvars
  os/
    variables.tf           # OS image mappings
    outputs.tf             # OS image lookup logic
  ansible/
    ansible.cfg            # Ansible connection settings
    inventory.tpl          # Inventory template (Terraform populates)
    inventories/
      dev/hosts.ini        # Generated (don't edit manually)
      uat/hosts.ini
      prod/hosts.ini
    site.yml               # Master playbook
    playbooks/
      base.yml             # Common config for all VMs
      webserver.yml        # Nginx + CloudForce web app
    templates/
      index.html.j2        # CloudForce landing page (Jinja2)
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
| `SkuNotAvailable` | Run `az vm list-skus --location westus --output table` and pick an available size |
| SSH timeout to web VM | Leave `admin_source_ip = null` for auto-detect, or set it to your current IP (`curl -s -4 ifconfig.me`) |
| Bastion won't connect | Bastion takes 5-10 min to provision. Check it's in `Succeeded` state in the portal |
| Ansible `UNREACHABLE` | Ensure Terraform finished, VM booted, and you're using the right `inventories/<env>/hosts.ini` |
| Web page blank | Run `ansible-playbook playbooks/webserver.yml` — nginx isn't installed until Ansible runs |
| `command not found: ansible-playbook` | Run `pip3 install ansible` |
| `coalesce` error with null | Ensure `locals.tf` uses `var.x != null ? var.x : ""` instead of `coalesce(var.x, "")` |
| privateVM can't reach internet | Enable NAT Gateway: `enable_nat_gateway = true` in tfvars |
| privateVM can't SSH to publicWebapp | Check web NSG has `allow-ssh-from-private-subnet` rule for 10.0.1.0/24 |
| Wrong environment | Run `terraform workspace show` and verify it matches your tfvars file |
