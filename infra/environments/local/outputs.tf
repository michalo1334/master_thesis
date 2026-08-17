output "urls" {
  description = "Local service URLs."
  value = {
    application = "http://127.0.0.1:4000"
    grafana     = "http://127.0.0.1:3000"
    pgadmin     = "http://127.0.0.1:5050"
    prometheus  = "http://127.0.0.1:9090"
  }
}
