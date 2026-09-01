application = {
  host      = "localhost"
  log_level = "debug"
  host_ports = {
    http     = 4000
    debugger = 9229
  }
}

database = {
  host_port = 5433
}

grafana = {
  host_port  = 3000
  admin_user = "admin"
}

pgadmin = {
  host_port   = 5050
  admin_email = "admin@admin.com"
}

prometheus = {
  host_port = 9090
}

secrets = {
  directory = "./secrets"
}
