{{- with secret "pki/issue/app-role" "common_name=app.example.com" "ttl=30s" -}}
{{ .Data.private_key }}
{{- end -}}