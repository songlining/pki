#!/bin/bash

# HashiCorp Vault PKI Certificate Issuance Demo
# Using demo-magic.sh for paced demonstrations

# Download demo-magic.sh if not present
if [ ! -f "demo-magic.sh" ]; then
    echo "Downloading demo-magic.sh..."
    curl -s https://raw.githubusercontent.com/paxtonhare/demo-magic/master/demo-magic.sh -o demo-magic.sh
    chmod +x demo-magic.sh
fi

# Source demo-magic
. ./demo-magic.sh

# Set demo speed
TYPE_SPEED=200
DEMO_PROMPT="${GREEN}$ ${CYAN}\W ${COLOR_RESET}"

# Vault configuration
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="myroot"

# Clean up previous demo artifacts
rm -f *.crt *.csr *.key *.pem *.txt 2>/dev/null

# Reset PKI engines for clean demo
echo "Cleaning up from previous demo runs..."
vault secrets disable pki_int 2>/dev/null || true
vault secrets disable pki 2>/dev/null || true
vault secrets enable pki 2>/dev/null || true
vault secrets enable -path=pki_int pki 2>/dev/null || true
vault secrets tune -max-lease-ttl=87600h pki 2>/dev/null || true
vault secrets tune -max-lease-ttl=43800h pki_int 2>/dev/null || true

# Demo title
echo -e "${BLUE}"
echo "==== HashiCorp Vault Enterprise PKI Certificate ===="
echo "==== Issuance Demo ===="
echo -e "${COLOR_RESET}"
echo ""

echo -e "${YELLOW}This demo shows how to use HashiCorp Vault Enterprise for PKI certificate management${COLOR_RESET}"
echo ""
wait

# Check Vault status
echo -e "${BLUE}"
echo "==== Step 1: Verify Vault Status ===="
echo -e "${COLOR_RESET}"
echo "Let's start by checking our Vault Enterprise instance:"
echo ""
pe "vault status"
echo ""
echo "OK: Vault Enterprise is running in development mode (auto-unsealed)"
wait

# Show enabled secrets engines
echo -e "${BLUE}"
echo "==== Step 2: Review PKI Secrets Engines ===="
echo -e "${COLOR_RESET}"
echo "Let's see what PKI secrets engines are already configured:"
echo ""
pe "vault secrets list"
echo ""
echo "Notice we have two PKI engines enabled:"
echo "  - pki/     - Root Certificate Authority (10-year max lease)"
echo "  - pki_int/ - Intermediate Certificate Authority (5-year max lease)"
wait

# Generate Root Certificate
echo -e "${BLUE}"
echo "==== Step 3: Generate Root Certificate ===="
echo -e "${COLOR_RESET}"
echo "First, let's generate a root certificate for our PKI:"
echo ""
p "vault write \\\\
  -field=certificate \\\\
  pki/root/generate/internal \\\\
  common_name=\"Demo Root CA\" \\\\
  country=\"AU\" \\\\
  organization=\"HashiCorp Demo\" \\\\
  ttl=87600h \\\\
  > root-ca.crt"
run_cmd "vault write -field=certificate pki/root/generate/internal common_name=\"Demo Root CA\" country=\"AU\" organization=\"HashiCorp Demo\" ttl=87600h > root-ca.crt"
echo ""
echo "Root certificate generated and saved to root-ca.crt"
pe "ls -la root-ca.crt"
wait

# Configure PKI URLs
echo -e "${BLUE}"
echo "==== Step 4: Configure PKI URLs ===="
echo -e "${COLOR_RESET}"
echo "Configure URLs for certificate and CRL distribution:"
echo ""
p "vault write pki/config/urls \\\\
  issuing_certificates=\"http://localhost:8200/v1/pki/ca\" \\\\
  crl_distribution_points=\"http://localhost:8200/v1/pki/crl\""
run_cmd "vault write pki/config/urls issuing_certificates=\"http://localhost:8200/v1/pki/ca\" crl_distribution_points=\"http://localhost:8200/v1/pki/crl\""
echo ""
echo "PKI URLs configured for certificate distribution"
wait

# Create intermediate CA
echo -e "${BLUE}"
echo "==== Step 5: Generate Intermediate Certificate ===="
echo -e "${COLOR_RESET}"
echo "Now let's create an intermediate certificate authority:"
echo ""
echo "Generate intermediate CSR:"
p "vault write \\\\
  -field=csr \\\\
  pki_int/intermediate/generate/internal \\\\
  common_name=\"Demo Intermediate CA\" \\\\
  country=\"AU\" \\\\
  organization=\"HashiCorp Demo\" \\\\
  > intermediate.csr"
run_cmd "vault write -field=csr pki_int/intermediate/generate/internal common_name=\"Demo Intermediate CA\" country=\"AU\" organization=\"HashiCorp Demo\" > intermediate.csr"

echo ""
echo "Sign intermediate CSR with root CA:"
p "vault write \\\\
  -field=certificate \\\\
  pki/root/sign-intermediate \\\\
  csr=@intermediate.csr \\\\
  format=pem_bundle \\\\
  ttl=43800h \\\\
  > intermediate.crt"
run_cmd "vault write -field=certificate pki/root/sign-intermediate csr=@intermediate.csr format=pem_bundle ttl=43800h > intermediate.crt"

echo ""
echo "Set signed certificate on intermediate CA:"
p "vault write pki_int/intermediate/set-signed \\\\
  certificate=@intermediate.crt"
run_cmd "vault write pki_int/intermediate/set-signed certificate=@intermediate.crt"

echo ""
echo "Intermediate CA configured and ready for certificate issuance"
wait

# Configure intermediate CA URLs
echo -e "${BLUE}"
echo "==== Step 6: Configure Intermediate CA URLs ===="
echo -e "${COLOR_RESET}"
echo "Configure URLs for the intermediate CA:"
echo ""
p "vault write pki_int/config/urls \\\\
  issuing_certificates=\"http://localhost:8200/v1/pki_int/ca\" \\\\
  crl_distribution_points=\"http://localhost:8200/v1/pki_int/crl\""
run_cmd "vault write pki_int/config/urls issuing_certificates=\"http://localhost:8200/v1/pki_int/ca\" crl_distribution_points=\"http://localhost:8200/v1/pki_int/crl\""
echo ""
echo "Intermediate CA URLs configured"
wait

# Create a role for certificate issuance
echo -e "${BLUE}"
echo "==== Step 7: Create Certificate Role ===="
echo -e "${COLOR_RESET}"
echo "Create a role that defines what types of certificates can be issued:"
echo ""
p "vault write pki_int/roles/web-server \\\\
  allowed_domains=\"example.com,demo.local\" \\\\
  allow_subdomains=true \\\\
  max_ttl=\"72h\" \\\\
  key_bits=2048 \\\\
  allow_any_name=false \\\\
  allow_localhost=true \\\\
  allow_ip_sans=true"
run_cmd "vault write pki_int/roles/web-server allowed_domains=\"example.com,demo.local\" allow_subdomains=true max_ttl=\"72h\" key_bits=2048 allow_any_name=false allow_localhost=true allow_ip_sans=true"
echo ""
echo "Certificate role 'web-server' created with domain restrictions"
wait

# Issue a certificate
echo -e "${BLUE}"
echo "==== Step 8: Issue a Server Certificate ===="
echo -e "${COLOR_RESET}"
echo "Now let's issue a certificate for a web server:"
echo ""
p "vault write \\\\
  pki_int/issue/web-server \\\\
  common_name=\"web.example.com\" \\\\
  alt_names=\"api.example.com,www.example.com\" \\\\
  ip_sans=\"127.0.0.1,192.168.1.100\" \\\\
  ttl=\"24h\" \\\\
  format=pem_bundle"
run_cmd "vault write pki_int/issue/web-server common_name=\"web.example.com\" alt_names=\"api.example.com,www.example.com\" ip_sans=\"127.0.0.1,192.168.1.100\" ttl=\"24h\" format=pem_bundle"
echo ""
echo "Certificate successfully issued!"
echo ""
echo "The response includes:"
echo "  - certificate: The issued certificate"
echo "  - private_key: The private key"
echo "  - ca_chain: The certificate chain"
echo "  - expiration: Unix timestamp of expiration"
wait

# Issue certificate with metadata
echo -e "${BLUE}"
echo "==== Step 8.5: Issue Certificate with Metadata ===="
echo -e "${COLOR_RESET}"
echo "HashiCorp Vault supports adding custom metadata to certificates:"
echo ""
echo "First, let's create metadata for our certificate:"
pe "echo '{\"department\": \"Engineering\", \"owner\": \"DevOps Team\", \"application\": \"Web Server\", \"environment\": \"Production\", \"cost_center\": \"CC-1001\"}' | base64 > cert_metadata.txt"
pe "cat cert_metadata.txt"

echo ""
echo "Now issue a certificate with metadata:"
p "vault write \\\\
  -field=serial_number \\\\
  pki_int/issue/web-server \\\\
  common_name=\"metadata.example.com\" \\\\
  ttl=\"24h\" \\\\
  cert_metadata=\$(cat cert_metadata.txt) \\\\
  > cert_serial.txt"
run_cmd "vault write -field=serial_number pki_int/issue/web-server common_name=\"metadata.example.com\" ttl=\"24h\" cert_metadata=\$(cat cert_metadata.txt) > cert_serial.txt"
pe "cat cert_serial.txt"

echo ""
echo "Certificate with metadata issued successfully!"
wait

# Save certificate components to files
echo -e "${BLUE}"
echo "==== Step 9: Save Certificate Components ===="
echo -e "${COLOR_RESET}"
echo "Let's save the certificate components to separate files for easier use:"
echo ""
p "vault write \\\\
  -field=certificate \\\\
  pki_int/issue/web-server \\\\
  common_name=\"app.example.com\" \\\\
  ttl=\"24h\" \\\\
  > app-cert.pem"
run_cmd "vault write -field=certificate pki_int/issue/web-server common_name=\"app.example.com\" ttl=\"24h\" > app-cert.pem"

p "vault write \\\\
  -field=private_key \\\\
  pki_int/issue/web-server \\\\
  common_name=\"api.example.com\" \\\\
  ttl=\"24h\" \\\\
  > api-key.pem"
run_cmd "vault write -field=private_key pki_int/issue/web-server common_name=\"api.example.com\" ttl=\"24h\" > api-key.pem"

p "vault write \\\\
  -field=ca_chain \\\\
  pki_int/issue/web-server \\\\
  common_name=\"backend.example.com\" \\\\
  ttl=\"24h\" \\\\
  > ca-chain.pem"
run_cmd "vault write -field=ca_chain pki_int/issue/web-server common_name=\"backend.example.com\" ttl=\"24h\" > ca-chain.pem"

echo ""
echo "Certificate files saved:"
pe "ls -la *.pem *.crt *.csr"
wait

# Retrieve certificate metadata
echo -e "${BLUE}"
echo "==== Step 10: Retrieve Certificate Metadata ===="
echo -e "${COLOR_RESET}"
echo "Let's retrieve and examine the certificate metadata we stored:"
echo ""
echo "List all certificates with metadata:"
pe "vault list pki_int/cert-metadata/"
echo ""
echo "Read metadata for our certificate:"
p "vault read \\\\
  pki_int/cert-metadata/\$(cat cert_serial.txt)"
run_cmd "vault read pki_int/cert-metadata/\$(cat cert_serial.txt)"
echo ""
echo "Decode the metadata to see the original JSON:"
p "vault read \\\\
  -field=cert_metadata \\\\
  pki_int/cert-metadata/\$(cat cert_serial.txt) \\\\
  | base64 -d"
run_cmd "vault read -field=cert_metadata pki_int/cert-metadata/\$(cat cert_serial.txt) | base64 -d"
echo ""
echo "Certificate metadata successfully retrieved and decoded!"
wait

# Verify certificate details
echo -e "${BLUE}"
echo "==== Step 11: Verify Certificate Details ===="
echo -e "${COLOR_RESET}"
echo "Let's examine the certificate we just issued:"
echo ""
p "openssl x509 \\\\
  -in app-cert.pem \\\\
  -text -noout \\\\
  | head -20"
run_cmd "openssl x509 -in app-cert.pem -text -noout | head -20"
echo ""
echo "Key certificate details:"
echo "  - Subject: Contains the common name we specified"
echo "  - Issuer: Signed by our Intermediate CA"
echo "  - Validity: 24-hour lifetime as requested"
echo "  - Extensions: Subject Alternative Names, Key Usage, etc."
wait

# Show certificate chain
echo -e "${BLUE}"
echo "==== Step 12: Examine Certificate Chain ===="
echo -e "${COLOR_RESET}"
echo "Let's verify our certificate chain is properly constructed:"
echo ""
echo "Certificate chain verification:"
p "openssl verify \\\\
  -CAfile root-ca.crt \\\\
  -untrusted intermediate.crt \\\\
  app-cert.pem"
run_cmd "openssl verify -CAfile root-ca.crt -untrusted intermediate.crt app-cert.pem"
echo ""
echo "Certificate chain is valid and properly signed!"
wait

# Revoke a certificate
echo -e "${BLUE}"
echo "==== Step 13: Certificate Revocation ===="
echo -e "${COLOR_RESET}"
echo "Demonstrate certificate revocation capabilities:"
echo ""
echo "First, let's issue a certificate specifically for revocation:"
p "vault write \\\\
  -field=serial_number \\\\
  pki_int/issue/web-server \\\\
  common_name=\"revoke-me.example.com\" \\\\
  ttl=\"1h\" \\\\
  > serial.txt"
run_cmd "vault write -field=serial_number pki_int/issue/web-server common_name=\"revoke-me.example.com\" ttl=\"1h\" > serial.txt"

echo ""
echo "Certificate serial number:"
pe "cat serial.txt"

echo ""
echo "Revoke the certificate:"
p "vault write pki_int/revoke \\\\
  serial_number=\$(cat serial.txt)"
run_cmd "vault write pki_int/revoke serial_number=\$(cat serial.txt)"

echo ""
echo "Certificate successfully revoked and added to CRL"
wait

# Show CRL
echo -e "${BLUE}"
echo "==== Step 14: Certificate Revocation List ===="
echo -e "${COLOR_RESET}"
echo "View the Certificate Revocation List:"
echo ""
p "curl -s \$VAULT_ADDR/v1/pki_int/crl/pem \\\\
  | openssl crl -inform PEM -text -noout"
run_cmd "curl -s \$VAULT_ADDR/v1/pki_int/crl/pem | openssl crl -inform PEM -text -noout"
echo ""
echo "The CRL shows our revoked certificate serial number"
wait

# Cleanup and summary
echo -e "${BLUE}"
echo "==== Demo Summary ===="
echo -e "${COLOR_RESET}"
echo ""
echo "${GREEN}PKI Demo Completed Successfully!${COLOR_RESET}"
echo ""
echo "What we accomplished:"
echo "  - Configured Vault Enterprise PKI engines"
echo "  - Generated root and intermediate Certificate Authorities"
echo "  - Created certificate roles with domain restrictions"
echo "  - Issued multiple server certificates with SANs and IP SANs"
echo "  - Added custom metadata to certificates for tracking"
echo "  - Retrieved and decoded certificate metadata"
echo "  - Saved certificate components to files"
echo "  - Verified certificate chain integrity"
echo "  - Demonstrated certificate revocation"
echo ""
echo "Generated files:"
pe "ls -la *.pem *.crt *.csr *.txt 2>/dev/null || echo 'No files generated in final demo run'"
echo ""
echo "${YELLOW}Next Steps:${COLOR_RESET}"
echo "  - Use certificates in your applications"
echo "  - Set up automatic certificate renewal"
echo "  - Configure certificate templates for different use cases"
echo "  - Integrate with CI/CD pipelines for automated certificate management"
echo ""
echo "${GREEN}Thank you for watching the HashiCorp Vault PKI Demo!${COLOR_RESET}"
echo ""
