locals {
  app = {
    environment      = local.app_environment
    healthcheck_path = "/readyz"
    image            = var.app_image
    mode             = var.app_mode
    port             = var.app_port
    secret_files     = local.app_secret_files
  }
  app_base_environment = [
    "REPO_USERNAME=${var.postgres_user}",
    "REPO_PASSWORD_FILE=/run/secrets/postgres-password",
    "REPO_HOSTNAME=${local.postgres_host}",
    "REPO_PORT=${local.postgres_port}",
    "REPO_DATABASE=${var.postgres_database}",
    "SECRET_KEY_BASE_FILE=/run/secrets/secret-key-base",
    "LIVE_VIEW_SIGNING_SALT_FILE=/run/secrets/live-view-signing-salt",
    "PHX_HOST=${var.phx_host}",
    "PORT=${var.app_port}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${var.otel_endpoint}",
    "OTEL_SERVICE_NAME=network_defense"
  ]
  app_environment = concat(local.app_base_environment, local.app_mode_environment)
  app_mode_environment = var.app_mode == "dev" ? [
    "LOG_FILE_LEVEL=${var.log_file_level}",
    "MIX_BUILD_PATH=/app/_build_docker",
    "PHX_IP=0.0.0.0"
    ] : [
    "ECTO_IPV6=true"
  ]
  app_replicas = var.app_replicas
  app_secret_files = [
    "erlang-cookie",
    "live-view-signing-salt",
    "postgres-password",
    "secret-key-base"
  ]
  name_prefix   = "network-defense-local"
  postgres_host = module.database.postgres_host
  postgres_port = module.database.postgres_port
  required_secret_files = distinct(concat([
    "grafana-admin-password",
    "pgadmin-password",
    "postgres-exporter-password",
    "postgres-password"
  ], local.app_secret_files))
  secret_mount_path = abspath(var.secret_mount_path)
}
