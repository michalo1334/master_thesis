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
  image_name = "network-defense-evaluation-compute:dev"
  log_level  = "info"
  pilot_limits = {
    max_outer_subsamples        = 128
    max_bootstrap_replicates    = 1024
    max_combined_bootstrap_work = 131072
  }
  process_count       = 1
  request_limit_bytes = 1048576
}

# Stage 4 Pilot resource caps. Deployment caps, not scientific settings.
pilot_limits = {
  snapshot_payload_bytes  = 2097152
  snapshot_comparisons    = 16
  comparison_count        = 16
  candidate_count         = 16
  plans_per_side          = 256
  attack_columns          = 512
  work_items              = 1024
  outer_subsamples        = 128
  bootstrap_replicates    = 1024
  candidate_request_bytes = 1048576
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
