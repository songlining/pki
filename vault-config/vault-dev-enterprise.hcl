storage "raft" {
  path    = "/vault/data"
  node_id = "node1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr = "http://0.0.0.0:8200"
cluster_addr = "http://0.0.0.0:8201"

ui = true

# Dev mode settings
disable_mlock = true
default_lease_ttl = "168h"
max_lease_ttl = "720h"

# License will be applied via API after startup