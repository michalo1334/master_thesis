locals {
  app = {
    environment      = local.app_environment
    healthcheck_path = "/readyz"
    image            = ""
    mode             = "dev"
    port             = var.application.host_ports.http
    secret_files     = local.app_secret_files
  }
  app_base_environment = [
    "REPO_USERNAME=${local.database_cfg.user}",
    "REPO_PASSWORD_FILE=/run/secrets/postgres-password",
    "REPO_HOSTNAME=${local.postgres_host}",
    "REPO_PORT=${local.postgres_port}",
    "REPO_DATABASE=${local.database_cfg.name}",
    "SECRET_KEY_BASE_FILE=/run/secrets/secret-key-base",
    "LIVE_VIEW_SIGNING_SALT_FILE=/run/secrets/live-view-signing-salt",
    "PHX_HOST=${var.application.host}",
    "PORT=${var.application.host_ports.http}",
    "ANALYSIS_SERVICE_URL=${module.analysis.internal_url}",
    "ANALYSIS_SERVICE_CONNECT_TIMEOUT_MS=5000",
    "ANALYSIS_SERVICE_TIMEOUT_MS=120000",
    "ANALYSIS_SERVICE_MAX_ZIP_BYTES=52428800",
    "OTEL_SERVICE_NAME=network_defense"
  ]
  app_environment = concat(local.app_base_environment, local.app_mode_environment)
  app_mode_environment = [
    "LOG_FILE_LEVEL=${var.application.log_level}",
    "MIX_BUILD_PATH=/app/_build_docker",
    "PHX_IP=0.0.0.0"
  ]
  all_host_ports = [
    var.application.host_ports.http,
    var.application.host_ports.metrics,
    var.application.host_ports.assets,
    var.application.host_ports.debugger,
    var.database.host_port,
    var.grafana.host_port,
    var.pgadmin.host_port,
    var.prometheus.host_port
  ]
  app_replicas = local.application.replicas[local.application.primary_site]
  app_secret_files = [
    "erlang-cookie",
    "live-view-signing-salt",
    "postgres-password",
    "secret-key-base"
  ]
  application  = module.deployment_config.application
  database_cfg = module.deployment_config.database
  legacy_host_ports = [
    4000,
    4001,
    5173,
    9229,
    5433,
    3000,
    5050,
    9090
  ]
  name_prefix   = module.deployment_config.config.name
  postgres_host = module.database.postgres_host
  postgres_port = module.database.postgres_port
  required_secret_files = distinct(concat([
    "pgadmin-password",
    "postgres-password"
  ], local.app_secret_files))
  secret_mount_path = abspath(var.secrets.directory)
}
