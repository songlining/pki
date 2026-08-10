{{- with secret "pki/issue/web-server" "common_name=app.example.com" "ttl=30s" -}}
{{ .Data.private_key }}
{{- end -}}