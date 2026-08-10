# =============================================================================
# modules/haproxy/main.tf
#
# Renders haproxy.cfg from a template and stores it in SSM Parameter Store.
# The HAProxy EC2 instance's user-data reads from SSM on boot and starts
# HAProxy automatically — no manual scp required.
#
# Uses built-in templatefile() — no deprecated hashicorp/template provider.
# =============================================================================

locals {
  backend_servers = [
    for idx, ip in var.master_private_ips :
    "  server ${var.name_prefix}-master-${idx + 1} ${ip}:${var.api_server_port} check fall 3 rise 2"
  ]

  haproxy_cfg = templatefile("${path.module}/../../templates/haproxy.cfg.tpl", {
    backend_servers = join("\n", local.backend_servers)
    maxconn         = var.haproxy_maxconn
    timeout_connect = var.haproxy_timeout_connect
    timeout_client  = var.haproxy_timeout_client
    timeout_server  = var.haproxy_timeout_server
    frontend_port   = var.api_server_port
    stats_port      = var.haproxy_stats_port
    stats_uri       = var.haproxy_stats_uri
  })
}

# Also write locally as a convenience artifact (useful for debugging)
resource "local_file" "haproxy_cfg" {
  content         = local.haproxy_cfg
  filename        = "${path.module}/../../../scripts/haproxy/haproxy.cfg"
  file_permission = "0644"
}
