# Environment variables for myapp.sh
CERT_FILE=/vault/agent/app.crt
PRIVATE_KEY_FILE=/vault/agent/app.key
CA_FILE=/vault/agent/ca.crt

# Certificate metadata for process tracking
{{- with secret "pki/issue/example-role" "common_name=app.example.com" "ttl=30s" }}
CERT_SERIAL={{ .Data.serial_number }}
{{- end }}