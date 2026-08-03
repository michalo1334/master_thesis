locals {
  base_secret_files = [
    "postgres-password",
    "secret-key-base",
    "live-view-signing-salt"
  ]
  secret_files = local.base_secret_files
  base_environment = [
    "REPO_USERNAME=${var.postgres_user}",
    "REPO_PASSWORD_FILE=/run/secrets/postgres-password",
    "REPO_HOSTNAME=${var.postgres_host}",
    "REPO_PORT=${var.postgres_port}",
    "REPO_DATABASE=${var.postgres_database}",
    "SECRET_KEY_BASE_FILE=/run/secrets/secret-key-base",
    "LIVE_VIEW_SIGNING_SALT_FILE=/run/secrets/live-view-signing-salt",
    "PHX_HOST=${var.phx_host}",
    "PORT=${var.app_port}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${var.otel_endpoint}",
    "OTEL_SERVICE_NAME=network_defense"
  ]
  mode_environment = var.app_mode == "dev" ? [
    "MIX_BUILD_PATH=/app/_build_docker",
    "PHX_IP=0.0.0.0",
    "LOG_FILE_PATH=${var.log_file_path}",
    "LOG_FILE_LEVEL=${var.log_file_level}"
  ] : [
    "ECTO_IPV6=true"
  ]
  environment = concat(local.base_environment, local.mode_environment)
}

output "configuration" {
  value = {
    mode            = var.app_mode
    image           = var.app_image
    environment     = local.environment
    port            = var.app_port
    healthcheck_path = "/readyz"
    secret_files    = local.secret_files
  }
}
