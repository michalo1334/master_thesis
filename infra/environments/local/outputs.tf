output "urls" {
  description = "Local service URLs."
  value = {
    application = "http://127.0.0.1:${var.application.host_ports.http}"
    database    = "postgresql://127.0.0.1:${var.database.host_port}"
    grafana     = "http://127.0.0.1:${var.grafana.host_port}"
    pgadmin     = "http://127.0.0.1:${var.pgadmin.host_port}"
    prometheus  = "http://127.0.0.1:${var.prometheus.host_port}"
  }
}

output "site_primary_node_names" {
  description = "Long node name for replica 0 of each site."
  value       = module.app.site_primary_node_names
}
