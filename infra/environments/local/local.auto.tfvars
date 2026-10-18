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

evaluation_compute = {
  container_port = 8080
  host_ports = {
    site-west = 8081
    site-east = 8082
  }
  image_name          = "network-defense-evaluation-compute:dev"
  log_level           = "info"
  process_count       = 1
  request_limit_bytes = 1048576
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
