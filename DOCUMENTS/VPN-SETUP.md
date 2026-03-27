# P2S VPN Gateway — Connect macOS, Windows, or Hyper-V to Azure

## Architecture

```
Your Mac / Windows / Hyper-V VM
        |
        | OpenVPN (TCP 443) or IKEv2 tunnel
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
|  myvm-subnet (10.0.1.0/24)     - privateVM        |
|  myvm-web-subnet (10.0.3.0/24) - publicWebapp     |
|  AzureBastionSubnet (10.0.2.0/26) - Bastion       |
+---------------------------------------------------+

VPN clients get IPs from: 172.16.0.0/24
```

Once connected, your client can SSH directly to `privateVM` at `10.0.1.4` and `publicWebapp` at `10.0.3.4` — no Bastion or public IP needed.

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
| `vpn-certs/rootCA.base64` | Base64 data to paste into Terraform |
| `vpn-certs/client.pem` | Client certificate (with clientAuth EKU) |
| `vpn-certs/client.key` | Client private key |
| `vpn-certs/client.pfx` | Client PKCS#12 bundle for macOS/Windows import |

**Important**: The client certificate must have Extended Key Usage `clientAuth` (OID 1.3.6.1.5.5.7.3.2). Without this, Azure VPN Gateway will reject the connection during TLS handshake. The included `generate-vpn-certs.sh` script handles this automatically.

---

## Step 2: Enable VPN in Terraform

Add to your tfvars:

```hcl
enable_vpn_gateway = true
vpn_root_cert_data = "<paste contents of vpn-certs/rootCA.base64 here>"
```

Or pass it on the command line:

```bash
terraform apply \
  -var="enable_vpn_gateway=true" \
  -var="vpn_root_cert_data=$(cat vpn-certs/rootCA.base64)"
```

**Warning**: VPN Gateway takes 30-45 minutes to provision and costs ~$140/month. You can `terraform destroy` it when not in use to save costs — the certs do not change.

---

## Step 3: Apply Terraform

```bash
terraform apply
```

After apply, note the public IP:

```bash
terraform output vpn_gateway_public_ip
```

---

## Step 4: Download VPN Client Configuration

### macOS / Linux (bash/zsh)

```bash
VPN_URL=$(az network vnet-gateway vpn-client generate \
  --name myvm-vpngw \
  --resource-group terraform-compute \
  --output tsv)

curl -o vpn-client.zip "$VPN_URL"
unzip -o vpn-client.zip -d vpn-client-config
```

### Windows (PowerShell)

```powershell
$vpnUrl = az network vnet-gateway vpn-client generate `
  --name myvm-vpngw `
  --resource-group terraform-compute `
  --output tsv

Invoke-WebRequest -Uri $vpnUrl -OutFile vpn-client.zip
Expand-Archive -Path .\vpn-client.zip -DestinationPath .\vpn-client-config -Force
```

The package contains:
- `OpenVPN/vpnconfig.ovpn` — OpenVPN profile (needs client cert/key embedded)
- `AzureVPN/azurevpnconfig.xml` — Azure VPN Client profile
- `Generic/VpnSettings.xml` — Server FQDN and settings for IKEv2
- `WindowsAmd64/` — Native Windows VPN installer

---

## Step 5: Prepare the OpenVPN Profile

The downloaded `.ovpn` file has placeholders for the client certificate. You must embed them before use.

Edit `vpn-client-config/OpenVPN/vpnconfig.ovpn`:

1. **Replace** `$CLIENTCERTIFICATE` in the `<cert>` block with the contents of `vpn-certs/client.pem`
2. **Replace** `$PRIVATEKEY` in the `<key>` block with the contents of `vpn-certs/client.key`
3. **Add** the VNet route after the `nobind` line:
   ```
   route 10.0.0.0 255.255.0.0 vpn_gateway
   ```
4. **Uncomment** `disable-dco` (required for OpenVPN Connect 3.x)
5. **Uncomment** `ping-restart 0` (prevents periodic reconnects)
6. **Remove** these lines (unsupported by OpenVPN Connect 3.x):
   - `log openvpn.log`
   - `resolv-retry infinite`
   - `persist-key`
   - `persist-tun`

Or run this one-liner to do it automatically:

```bash
CLIENT_PEM=$(cat vpn-certs/client.pem)
CLIENT_KEY=$(cat vpn-certs/client.key)

sed -i.bak \
  -e "s|\\\$CLIENTCERTIFICATE|${CLIENT_PEM}|" \
  -e "s|\\\$PRIVATEKEY|${CLIENT_KEY}|" \
  -e 's/^#disable-dco/disable-dco/' \
  -e 's/^#ping-restart 0/ping-restart 0/' \
  -e '/^log /d' \
  -e '/^resolv-retry /d' \
  -e '/^persist-key/d' \
  -e '/^persist-tun/d' \
  vpn-client-config/OpenVPN/vpnconfig.ovpn

# Add VNet route if not already present
grep -q "route 10.0.0.0" vpn-client-config/OpenVPN/vpnconfig.ovpn || \
  sed -i.bak '/^nobind/a\
\
# Route Azure VNet traffic through the VPN tunnel\
route 10.0.0.0 255.255.0.0 vpn_gateway' vpn-client-config/OpenVPN/vpnconfig.ovpn

rm -f vpn-client-config/OpenVPN/vpnconfig.ovpn.bak
```

---

## Step 6: Connect from macOS

### Option A: OpenVPN Connect (recommended — tested and working)

1. Install **OpenVPN Connect** from the Mac App Store or `brew install --cask openvpn-connect`
2. Open OpenVPN Connect
3. Go to **Import Profile** > **From File**
4. Select the prepared `vpn-client-config/OpenVPN/vpnconfig.ovpn`
5. Click **Connect**

Alternatively, use the CLI:

```bash
brew install openvpn
sudo /opt/homebrew/opt/openvpn/sbin/openvpn \
  --config vpn-client-config/OpenVPN/vpnconfig.ovpn
```

### Option B: Native macOS IKEv2

1. Import the client certificate into Keychain:
   ```bash
   open vpn-certs/client.pfx
   ```
   Leave the password **empty** when prompted.

2. Open **System Settings** > **VPN** > **Add VPN Configuration** > **IKEv2**

3. Fill in:
   - **Display Name**: `CloudForce VPN`
   - **Server Address**: the `VpnServer` FQDN from `vpn-client-config/Generic/VpnSettings.xml`
   - **Remote ID**: same as Server Address
   - **Local ID**: `CloudForceVPNClient`
   - **Authentication**: Certificate
   - **Certificate**: Select `CloudForceVPNClient`

4. Click **Create**, then toggle the VPN on.

---

## Step 7: Connect from Windows

### Option A: Native Windows VPN (IKEv2)

#### 1. Import the client certificate

Copy `vpn-certs/client.pfx` to the Windows machine and double-click it.

In the import wizard:
- **Store Location**: Current User
- **Password**: leave empty
- **Certificate Store**: Personal

#### 2. Install the VPN profile

From the extracted package, run the installer:
- `vpn-client-config\WindowsAmd64\VpnClientSetupAmd64.exe` (64-bit)
- `vpn-client-config\WindowsX86\VpnClientSetupX86.exe` (32-bit)

If SmartScreen appears: click **More info** > **Run anyway**.

#### 3. Connect

Go to **Settings** > **Network & Internet** > **VPN**. Select the connection and click **Connect**. If prompted, select the `CloudForceVPNClient` certificate.

### Option B: OpenVPN Connect on Windows

1. Download and install **OpenVPN Connect** from https://openvpn.net/client/
2. Open OpenVPN Connect
3. Go to **Import Profile** > **From File**
4. Select the prepared `vpn-client-config\OpenVPN\vpnconfig.ovpn`
5. Click **Connect**

### Option C: Azure VPN Client on Windows (OpenVPN)

1. Install **Azure VPN Client** from the Microsoft Store
2. Ensure `client.pfx` is imported into `Current User > Personal`
3. Click **+** > **Import** > select `vpn-client-config\AzureVPN\azurevpnconfig.xml`
4. In the profile, set **Client Certificate Public key Data** and **Private Key** from `vpn-certs/client.pem` and `vpn-certs/client.key` (base64 DER encoded)
5. Click **Save** and **Connect**

---

## Step 8: Connect from Hyper-V VMs (P2S per-VM)

If you want individual Hyper-V VMs to connect to Azure, install a VPN client inside each VM. This is the simplest approach and uses the same P2S gateway.

### Windows VM on Hyper-V

1. Copy the following files to the VM (via shared folder, USB, or RDP):
   - `vpn-certs/client.pfx`
   - `vpn-client-config/` folder (or just the `WindowsAmd64` and `OpenVPN` subdirectories)

2. **Option A: Native IKEv2** (simplest)
   - Double-click `client.pfx` to import (Current User > Personal, empty password)
   - Run `vpn-client-config\WindowsAmd64\VpnClientSetupAmd64.exe`
   - Go to **Settings** > **Network & Internet** > **VPN** > Connect

3. **Option B: OpenVPN Connect**
   - Install OpenVPN Connect inside the VM
   - Import the prepared `vpnconfig.ovpn`
   - Connect

### Linux VM on Hyper-V

1. Copy these files to the VM:
   - `vpn-client-config/OpenVPN/vpnconfig.ovpn` (already prepared with certs embedded)

2. Install OpenVPN:
   ```bash
   # Ubuntu/Debian
   sudo apt update && sudo apt install -y openvpn

   # RHEL/CentOS
   sudo yum install -y openvpn
   ```

3. Connect:
   ```bash
   sudo openvpn --config vpnconfig.ovpn
   ```

4. To run as a persistent service:
   ```bash
   sudo cp vpnconfig.ovpn /etc/openvpn/client/azure.conf
   sudo systemctl enable --now openvpn-client@azure
   ```

### Multiple VPN Clients

Each client gets a unique IP from `172.16.0.0/24`. You can connect multiple machines simultaneously using the same `client.pfx` certificate. For better security in production, generate a separate client certificate per device using the same root CA:

```bash
# Generate a second client cert (signed by the same root CA)
openssl req -new -nodes -newkey rsa:2048 \
  -keyout vpn-certs/client2.key \
  -out vpn-certs/client2.csr \
  -subj "/CN=CloudForceVPNClient2" 2>/dev/null

openssl x509 -req \
  -in vpn-certs/client2.csr \
  -CA vpn-certs/rootCA.pem \
  -CAkey vpn-certs/rootCA.key \
  -CAcreateserial \
  -out vpn-certs/client2.pem \
  -days 3650 \
  -extfile <(printf '[ext]\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth') \
  -extensions ext 2>/dev/null

openssl pkcs12 -export \
  -out vpn-certs/client2.pfx \
  -inkey vpn-certs/client2.key \
  -in vpn-certs/client2.pem \
  -certfile vpn-certs/rootCA.pem \
  -passout pass: \
  -macalg sha1 \
  -keypbe pbeWithSHA1And3-KeyTripleDES-CBC \
  -certpbe pbeWithSHA1And3-KeyTripleDES-CBC

rm -f vpn-certs/client2.csr vpn-certs/rootCA.srl
```

No changes needed on the Azure side — any client cert signed by the uploaded root CA is accepted.

---

## Step 9: Connect Entire Hyper-V Network (Site-to-Site)

If you want **all** VMs on your Hyper-V host to reach Azure without installing a VPN client on each one, you need a Site-to-Site (S2S) VPN. This runs alongside the existing P2S gateway.

### What you need at home

A VPN appliance (physical or virtual) acting as your home network's gateway:

| Appliance | Type | Notes |
|---|---|---|
| **VyOS** | VM on Hyper-V | Free, on Azure's validated device list |
| **pfSense** | VM on Hyper-V | Free, well-documented |
| **OPNsense** | VM on Hyper-V | Free pfSense fork |
| **Windows RRAS** | Windows Server role | No extra VM if host runs Server |

### Prerequisites

- Your home lab needs a **public IP** that Azure can reach. If your ISP uses CGNAT, S2S won't work — use P2S per-VM instead.
- Home and Azure subnets **must not overlap** (home = `192.168.1.0/24`, Azure = `10.0.0.0/16`).

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
Azure VPN Gateway (myvm-vpngw)
    |
    +-- cloudforce-vnet (10.0.0.0/16)
          +-- privateVM (10.0.1.x)
          +-- publicWebapp (10.0.3.x)
```

### Terraform resources for S2S

Add these to your Terraform config:

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

These are not in the repo yet — add them when you are ready.

### VyOS quick-start config (home side)

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

## Step 10: Verify Connectivity

Once connected, your client gets an IP from `172.16.0.0/24` and can reach everything in the VNet directly.

### Quick reference IPs

| Resource | IP |
|---|---|
| VPN Gateway (public) | `terraform output vpn_gateway_public_ip` |
| privateVM (private) | 10.0.1.4 |
| publicWebapp (private) | 10.0.3.4 |
| publicWebapp (public) | `terraform output web_vm_public_ip` |
| Your VPN client | 172.16.0.x (assigned on connect) |

### Test from macOS / Linux

```bash
# Check VPN tunnel IP
ifconfig utun11    # tunnel number may vary

# SSH to privateVM
ssh -i ~/.ssh/azure_rsa azureuser@10.0.1.4

# SSH to publicWebapp over internal network
ssh -i ~/.ssh/azure_rsa azureuser@10.0.3.4

# Reach web app internally
curl http://10.0.3.4
```

### Test from Windows / Hyper-V VM

```powershell
# Check VPN-assigned IP
ipconfig

# SSH to privateVM
ssh -i $HOME\.ssh\azure_rsa azureuser@10.0.1.4

# SSH to publicWebapp
ssh -i $HOME\.ssh\azure_rsa azureuser@10.0.3.4

# Reach web app internally
curl http://10.0.3.4
```

No Bastion is required for day-to-day access once the VPN is connected.

---

## Cost

| Resource | Approx monthly cost |
|---|---|
| VPN Gateway (VpnGw1) | ~$140 |
| VPN Gateway public IP | ~$4 |
| Data transfer (outbound) | ~$0.05/GB |

**Tip**: Destroy the VPN gateway when not in use (`terraform destroy -target=azurerm_virtual_network_gateway.vpn`) and recreate when needed. The certificates do not change.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| OpenVPN: `EOF received on TCP network socket` | Client certificate is missing `clientAuth` EKU. Regenerate with `./generate-vpn-certs.sh` (the script now includes EKU). |
| OpenVPN: `Connection timeout / General tun error` | Enable `disable-dco` and `ping-restart 0` in the `.ovpn` file. Remove `log`, `resolv-retry`, `persist-key`, `persist-tun`. |
| OpenVPN: Connected but can't reach VMs | Add `route 10.0.0.0 255.255.0.0 vpn_gateway` to the `.ovpn` file. Verify with `netstat -rn \| grep 10.0`. |
| macOS IKEv2: Sits on "Connecting..." | Import both `VpnServerRoot.cer` (from `Generic/`) and `client.pfx` into login keychain. Use FQDN (not IP) for Server Address and Remote ID. |
| macOS: PFX import fails | Regenerate PFX with legacy format: `openssl pkcs12 -export -macalg sha1 -keypbe pbeWithSHA1And3-KeyTripleDES-CBC -certpbe pbeWithSHA1And3-KeyTripleDES-CBC ...` |
| Windows: VPN installer SmartScreen | Click **More info** > **Run anyway**. |
| Windows: Azure VPN Client shows no certificate | Remove duplicate certs and re-import `client.pfx` into Current User > Personal. |
| SSH times out over VPN | Check NSG allows SSH from `172.16.0.0/24`. Run `terraform apply` to update rules. |
| VPN Gateway stuck provisioning | Normal — takes 30-45 min. Check Azure Portal for status. |
| S2S: ISP uses CGNAT | S2S requires a reachable public IP. Use P2S per-VM instead. |
| S2S: Tunnel drops | Verify IKE/ESP settings match between VyOS/pfSense and Azure. |
