pid_file = "/tmp/pidfile-cert"

vault {
  address = "https://vault.local:8200"
  ca_cert = "/vault/tls/vault-ca.pem"
}

auto_auth {
  enable_reauth_on_new_credentials = true

  method "cert" {
    mount_path = "auth/cert"
    config = {
      name          = "host-role"
      ca_cert       = "/vault/tls/vault-ca.pem"
      client_cert   = "/vault/config/host.pem"
      client_key    = "/vault/config/host.pem"
      reload        = true
      reload_period = "5s"
    }
  }

  sink "file" {
    config = {
      path = "/tmp/vault-token-cert"
    }
  }
}

cache {
  use_auto_auth_token = true
}

template_config {
  lease_renewal_threshold = 0.95
}

listener "tcp" {
  address     = "0.0.0.0:8101"
  tls_disable = true
}

template {
  source      = "/vault/config/host-bundle.tpl"
  destination = "/vault/config/host.pem"
  perms       = 0600
}

template {
  source      = "/vault/config/cert.tpl"
  destination = "/vault/agent/app.crt"
  perms       = 0644
}

template {
  source      = "/vault/config/key.tpl"
  destination = "/vault/agent/app.key"
  perms       = 0600
}

template {
  source      = "/vault/config/ca.tpl"
  destination = "/vault/agent/ca.crt"
  perms       = 0644
}

template {
  source      = "/vault/config/env.tpl"
  destination = "/vault/agent/app.env"
  perms       = 0644
  command     = "/bin/sh /vault/config/restart-app.sh"
}
