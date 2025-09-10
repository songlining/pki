{{- with secret "pki/issue/example-role" "common_name=app.example.com" "ttl=24h" -}}
{{ .Data.private_key }}
{{- end -}}