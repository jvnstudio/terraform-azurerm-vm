#!/bin/bash
# Generate self-signed root CA and client certificates for Azure P2S VPN.
# Usage: ./generate-vpn-certs.sh
#
# Output:
#   vpn-certs/rootCA.pem          - Root CA certificate
#   vpn-certs/rootCA.key          - Root CA private key
#   vpn-certs/rootCA.base64       - Base64 cert data (paste into Terraform)
#   vpn-certs/client.pem          - Client certificate
#   vpn-certs/client.key          - Client private key
#   vpn-certs/client.pfx          - Client PKCS#12 bundle (for macOS/Windows import)

set -euo pipefail

CERT_DIR="vpn-certs"
mkdir -p "$CERT_DIR"

echo "==> Generating Root CA..."
openssl req -x509 -new -nodes \
  -newkey rsa:2048 \
  -keyout "$CERT_DIR/rootCA.key" \
  -out "$CERT_DIR/rootCA.pem" \
  -days 3650 \
  -subj "/CN=CloudForceVPNRootCA" \
  2>/dev/null

echo "==> Generating client certificate..."
openssl req -new -nodes \
  -newkey rsa:2048 \
  -keyout "$CERT_DIR/client.key" \
  -out "$CERT_DIR/client.csr" \
  -subj "/CN=CloudForceVPNClient" \
  2>/dev/null

openssl x509 -req \
  -in "$CERT_DIR/client.csr" \
  -CA "$CERT_DIR/rootCA.pem" \
  -CAkey "$CERT_DIR/rootCA.key" \
  -CAcreateserial \
  -out "$CERT_DIR/client.pem" \
  -days 3650 \
  2>/dev/null

rm -f "$CERT_DIR/client.csr" "$CERT_DIR/rootCA.srl"

echo "==> Creating client .pfx bundle (press Enter for empty password)..."
openssl pkcs12 -export \
  -out "$CERT_DIR/client.pfx" \
  -inkey "$CERT_DIR/client.key" \
  -in "$CERT_DIR/client.pem" \
  -certfile "$CERT_DIR/rootCA.pem" \
  -passout pass:

echo "==> Extracting Base64 root cert data for Terraform..."
openssl x509 -in "$CERT_DIR/rootCA.pem" -outform der | base64 > "$CERT_DIR/rootCA.base64"

echo ""
echo "===== Done ====="
echo ""
echo "Certificates are in: $CERT_DIR/"
echo ""
echo "Next steps:"
echo ""
echo "  1. Add the root cert to your Terraform config:"
echo ""
echo "     vpn_root_cert_data = \"$(cat "$CERT_DIR/rootCA.base64")\""
echo ""
echo "  2. Run: terraform apply"
echo ""
echo "  3. Import the client cert on your Mac:"
echo "     open $CERT_DIR/client.pfx"
echo "     (This opens Keychain Access — click Add, leave password empty)"
echo ""
echo "  4. Download the VPN client config from Azure:"
echo "     az network vnet-gateway vpn-client generate \\"
echo "       --name myvm-vpngw \\"
echo "       --resource-group terraform-compute \\"
echo "       --output tsv"
echo ""
echo "  5. Install Azure VPN Client from the App Store and import the config."
