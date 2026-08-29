output "urls" {
  description = "Local service URLs."
  value = {
    application = "http://127.0.0.1:${var.application.host_ports.http}"
    database    = "postgresql://127.0.0.1:${var.database.host_port}"
    pgadmin     = "http://127.0.0.1:${var.pgadmin.host_port}"
  }
}
