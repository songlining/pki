pid_file = "/tmp/pidfile"

vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/vault/config/role-id"
      secret_id_file_path = "/vault/config/secret-id"
    }
  }

  sink "file" {
    config = {
      path = "/tmp/vault-token"
    }
  }
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address = "0.0.0.0:8100"
  tls_disable = true
}

template {
  source = "/vault/config/cert.tpl"
  destination = "/vault/agent/app.crt"
  perms = 0644
}

template {
  source = "/vault/config/key.tpl"
  destination = "/vault/agent/app.key"
  perms = 0600
}

template {
  source = "/vault/config/ca.tpl"
  destination = "/vault/agent/ca.crt"
  perms = 0644
}