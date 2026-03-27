# P2S VPN Gateway — Connect Mac/Hyper-V to Azure

## Architecture

```
Your Mac / Hyper-V Home Lab
        |
        | IKEv2 or OpenVPN tunnel
        | (encrypted over internet)
        v
+---------------------+
| Azure VPN Gateway   |
| myvm-vpngw          |
| Public IP           |
| GatewaySubnet       |
| 10.0.4.0/27         |
+---------------------+
        |
        | Routes to all subnets in cloudforce-vnet
        v
+---------------------------------------------------+
| cloudforce-vnet (10.0.0.0/16)                     |
|                                                   |
|  myvm-subnet (10.0.1.0/24)    - privateVM         |
|  myvm-web-subnet (10.0.3.0/24) - publicWebapp     |
|  AzureBastionSubnet (10.0.2.0/26) - Bastion       |
+---------------------------------------------------+

VPN clients get IPs from: 172.16.0.0/24
```

Once connected, your Mac can directly SSH to `privateVM` at its private IP (e.g., `10.0.1.4`) — no Bastion needed.

---

## Step 1: Generate Certificates

Azure P2S VPN uses certificate-based authentication. Run the included script:

```bash
./generate-vpn-certs.sh
```

This creates:
| File | Purpose |
|---|---|
| `vpn-certs/rootCA.pem` | Root CA certificate |
| `vpn-certs/rootCA.key` | Root CA private key (keep safe) |
| `vpn-certs/rootCA.base64` | Base64 data for Terraform |
| `vpn-certs/client.pem` | Client certificate |
| `vpn-certs/client.key` | Client private key |
| `vpn-certs/client.pfx` | Client bundle for macOS/Windows import |

---

## Step 2: Enable VPN in Terraform

Add to your tfvars (e.g., `environments/dev/terraform.tfvars` or `terraform.tfvars`):

```hcl
enable_vpn_gateway = true
vpn_root_cert_data = "<paste contents of vpn-certs/rootCA.base64 here>"
```

Or set it from the command line:

```bash
terraform apply \
  -var="enable_vpn_gateway=true" \
  -var="vpn_root_cert_data=$(cat vpn-certs/rootCA.base64)"
```

**Warning: VPN Gateway takes 30-45 minutes to provision and costs ~$140/month.**

---

## Step 3: Apply Terraform

```bash
terraform apply
```

Wait for it to finish. The VPN Gateway is the slowest resource.

After apply, note the output:
```bash
terraform output vpn_gateway_public_ip
```

---

## Step 4: Install Client Certificate on Mac

Double-click the `.pfx` file to import into Keychain:

```bash
open vpn-certs/client.pfx
```

When prompted for a password, leave it **empty** and click OK. The certificate will appear in Keychain Access under "login".

---

## Step 5: Download VPN Client Configuration

```bash
az network vnet-gateway vpn-client generate \
  --name myvm-vpngw \
  --resource-group terraform-compute \
  --output tsv
```

This returns a URL. Download the zip file:

```bash
VPN_URL=$(az network vnet-gateway vpn-client generate \
  --name myvm-vpngw \
  --resource-group terraform-compute \
  --output tsv)

curl -o vpn-client.zip "$VPN_URL"
unzip vpn-client.zip -d vpn-client-config
```

---

## Step 6: Connect from Mac

### Option A: Azure VPN Client (recommended)

1. Install **Azure VPN Client** from the Mac App Store
2. Open the app, click **+** (import)
3. Navigate to `vpn-client-config/AzureVPN/azurevpnconfig.xml`
4. Click **Import**, then **Connect**

### Option B: Native macOS IKEv2

1. Go to **System Settings** > **VPN** > **Add VPN Configuration** > **IKEv2**
2. Configure:
   - **Display Name**: CloudForce VPN
   - **Server Address**: `<vpn_gateway_public_ip from terraform output>`
   - **Remote ID**: `<vpn_gateway_public_ip>`
   - **Local ID**: (leave blank)
   - **Authentication**: Certificate
   - **Certificate**: Select `CloudForceVPNClient` from Keychain
3. Click **Create**, then toggle the VPN on

---

## Step 7: Verify Connectivity

Once connected:

```bash
# Check your VPN-assigned IP (should be 172.16.0.x)
ifconfig utun0    # or utun1, utun2 — check which tunnel is active

# SSH directly to privateVM using its private IP
ssh -i ~/.ssh/azure_rsa azureuser@10.0.1.4

# Reach publicWebapp internally
curl http://10.0.3.4

# Verify DNS resolution (if using Azure DNS)
nslookup privateVM.internal.cloudapp.net
```

No more Bastion needed for day-to-day SSH.

---

## Connecting Hyper-V Home Lab (Site-to-Site)

If you want your entire Hyper-V network to talk to Azure (not just your Mac), you need a Site-to-Site VPN. This is a future addition on top of the P2S gateway.

### What you need at home

A VPN appliance (physical or virtual) running on or alongside your Hyper-V host. Options:

| Appliance | Type | Notes |
|---|---|---|
| **VyOS** | VM on Hyper-V | Free, on Azure's validated device list |
| **pfSense** | VM on Hyper-V | Free, well-documented |
| **OPNsense** | VM on Hyper-V | Free, pfSense fork |
| **Windows RRAS** | Built-in to Windows Server | No extra VM needed if your Hyper-V host is Server |

### Network layout

```
Home Lab (192.168.1.0/24)
    |
    +-- Hyper-V Host
    |     +-- VyOS/pfSense VM (edge router)
    |     +-- Lab VMs (192.168.1.x)
    |
    | IPsec tunnel (S2S)
    v
Azure VPN Gateway
    |
    +-- cloudforce-vnet (10.0.0.0/16)
          +-- privateVM (10.0.1.x)
          +-- publicWebapp (10.0.3.x)
```

### Prerequisites for S2S
- Your home lab needs a **public IP** (or FQDN) that Azure can reach. If your ISP uses CGNAT, S2S won't work — stick with P2S.
- Your home and Azure subnets **must not overlap** (e.g., home=`192.168.1.0/24`, Azure=`10.0.0.0/16`).

### Additional Terraform resources needed for S2S

```hcl
# Represents your home network
resource "azurerm_local_network_gateway" "home" {
  name                = "home-lab-lng"
  location            = var.location
  resource_group_name = azurerm_resource_group.vm.name
  gateway_address     = "<your-home-public-ip>"
  address_space       = ["192.168.1.0/24"]
}

# The IPsec tunnel
resource "azurerm_virtual_network_gateway_connection" "home" {
  name                       = "home-lab-connection"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.vm.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn[0].id
  local_network_gateway_id   = azurerm_local_network_gateway.home.id
  shared_key                 = "<pre-shared-key>"
}
```

These are not yet in the repo — they'll be added when you're ready to set up the home-lab VPN appliance.

### VyOS quick-start config (on the home side)

```
set vpn ipsec ike-group AZURE-IKE proposal 1 encryption aes256
set vpn ipsec ike-group AZURE-IKE proposal 1 hash sha256
set vpn ipsec ike-group AZURE-IKE key-exchange ikev2

set vpn ipsec esp-group AZURE-ESP proposal 1 encryption aes256
set vpn ipsec esp-group AZURE-ESP proposal 1 hash sha256

set vpn ipsec site-to-site peer <azure-vpngw-public-ip> authentication mode pre-shared-secret
set vpn ipsec site-to-site peer <azure-vpngw-public-ip> authentication pre-shared-secret '<pre-shared-key>'
set vpn ipsec site-to-site peer <azure-vpngw-public-ip> ike-group AZURE-IKE
set vpn ipsec site-to-site peer <azure-vpngw-public-ip> default-esp-group AZURE-ESP
set vpn ipsec site-to-site peer <azure-vpngw-public-ip> local-address <vyos-public-ip>
set vpn ipsec site-to-site peer <azure-vpngw-public-ip> tunnel 1 local prefix 192.168.1.0/24
set vpn ipsec site-to-site peer <azure-vpngw-public-ip> tunnel 1 remote prefix 10.0.0.0/16
```

---

## Cost Considerations

| Resource | Approx monthly cost |
|---|---|
| VPN Gateway (VpnGw1) | ~$140 |
| VPN Gateway public IP | ~$4 |
| Data transfer (outbound) | ~$0.05/GB |

**Tip**: If you only need occasional access, you can `terraform destroy` the VPN gateway when not in use and recreate it when needed. The certs don't change.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| VPN client can't connect | Verify root cert was uploaded correctly: `az network vnet-gateway show --name myvm-vpngw --resource-group terraform-compute --query vpnClientConfiguration` |
| Connected but can't reach VMs | Check NSG has `allow-ssh-from-vpn-clients` rule for `172.16.0.0/24` |
| Certificate errors | Regenerate certs with `./generate-vpn-certs.sh` and re-import `.pfx` |
| Gateway stuck provisioning | VPN Gateways take 30-45 min. Check portal for status |
| S2S: ISP uses CGNAT | S2S requires a reachable public IP. Use P2S instead |
| S2S: Tunnel drops | Check IKE/ESP settings match between VyOS and Azure |
