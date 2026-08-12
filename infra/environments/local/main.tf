locals {
  name_prefix       = "network-defense-local"
  secret_mount_path = abspath(var.secret_mount_path)
  postgres_host     = module.database.postgres_host
  postgres_port     = module.database.postgres_port
  app_secret_files = [
    "postgres-password",
    "secret-key-base",
    "live-view-signing-salt"
  ]
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
  app_mode_environment = var.app_mode == "dev" ? [
    "MIX_BUILD_PATH=/app/_build_docker",
    "PHX_IP=0.0.0.0",
    "LOG_FILE_PATH=${var.log_file_path}",
    "LOG_FILE_LEVEL=${var.log_file_level}"
    ] : [
    "ECTO_IPV6=true"
  ]
  app_environment = concat(local.app_base_environment, local.app_mode_environment)
  app = {
    mode             = var.app_mode
    image            = var.app_image
    environment      = local.app_environment
    port             = var.app_port
    healthcheck_path = "/readyz"
    secret_files     = local.app_secret_files
  }
  required_secret_files = distinct(concat([
    "postgres-password",
    "postgres-exporter-password",
    "grafana-admin-password",
    "pgadmin-password"
  ], local.app_secret_files))
}

resource "docker_network" "stack" {
  name = "${local.name_prefix}-network"

  lifecycle {
    precondition {
      condition = alltrue([
        for filename in local.required_secret_files : fileexists("${local.secret_mount_path}/${filename}")
      ])
      error_message = "Secret directory must contain: ${join(", ", local.required_secret_files)}."
    }
  }
}

resource "docker_volume" "application_logs" {
  name = "${local.name_prefix}-logs"
}

module "database" {
  source = "../../modules/local/database"

  name_prefix       = local.name_prefix
  network_name      = docker_network.stack.name
  secret_mount_path = local.secret_mount_path
  postgres_user     = var.postgres_user
  postgres_database = var.postgres_database
  pgadmin_email     = var.pgadmin_email
}

module "app" {
  source = "../../modules/local/app"

  name_prefix       = local.name_prefix
  app_source_path   = abspath("${path.module}/../../../src")
  network_name      = docker_network.stack.name
  secret_mount_path = local.secret_mount_path
  log_volume_name   = docker_volume.application_logs.name
  app               = local.app

  depends_on = [module.database]
}

module "observability" {
  source = "../../modules/local/observability"

  name_prefix       = local.name_prefix
  config_path       = abspath("${path.module}/../../../docker")
  network_name      = docker_network.stack.name
  secret_mount_path = local.secret_mount_path
  log_volume_name   = docker_volume.application_logs.name
  postgres_user     = var.postgres_user
  postgres_database = var.postgres_database
  postgres_host     = local.postgres_host
  postgres_port     = local.postgres_port
  postgres_image    = module.database.postgres_image
  grafana_user      = var.grafana_user

  depends_on = [module.database]
}

output "urls" {
  value = {
    application = "http://127.0.0.1:4000"
    grafana     = "http://127.0.0.1:3000"
    pgadmin     = "http://127.0.0.1:5050"
    prometheus  = "http://127.0.0.1:9090"
  }
}
