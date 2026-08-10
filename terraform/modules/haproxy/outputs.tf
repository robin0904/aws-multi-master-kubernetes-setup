# =============================================================================
# modules/haproxy/outputs.tf
# =============================================================================

output "haproxy_cfg_content" {
  description = "Fully rendered haproxy.cfg content. Passed to the SSM module for storage."
  value       = local.haproxy_cfg
}
