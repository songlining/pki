{{- with pkiCert "pki/issue/host-role" "common_name=host-01.trading.demo.internal" "ttl=30s" -}}
{{ .Cert }}
{{ .Key }}
{{- end -}}
