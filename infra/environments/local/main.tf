locals {
  name_prefix       = "network-defense-local"
  secret_mount_path = abspath(var.secret_mount_path)
  required_secret_files = distinct(concat([
    "postgres-password",
    "postgres-exporter-password",
    "grafana-admin-password",
    "pgadmin-password"
  ], module.app.configuration.secret_files))
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

module "local" {
  source = "../../modules/local"

  name_prefix       = local.name_prefix
  network_name      = docker_network.stack.name
  secret_mount_path = local.secret_mount_path
  postgres_user     = var.postgres_user
  postgres_database = var.postgres_database
  pgadmin_email     = var.pgadmin_email
}

module "app" {
  source = "../../modules/app"

  app_mode          = var.app_mode
  app_image         = var.app_image
  postgres_user     = var.postgres_user
  postgres_database = var.postgres_database
  postgres_host     = "postgres"
  postgres_port     = 5432
  phx_host          = var.phx_host
  app_port          = var.app_port
  otel_endpoint     = var.otel_endpoint
  log_file_path     = var.log_file_path
  log_file_level    = var.log_file_level
}

module "local_app" {
  source = "../../modules/local/app"

  name_prefix       = local.name_prefix
  app_source_path   = abspath("${path.module}/../../../src")
  network_name      = docker_network.stack.name
  secret_mount_path = local.secret_mount_path
  log_volume_name   = docker_volume.application_logs.name
  app               = module.app.configuration

  depends_on = [module.local]
}

module "observability" {
  source = "../../modules/observability"

  name_prefix       = local.name_prefix
  config_path       = abspath("${path.module}/../../../docker")
  network_name      = docker_network.stack.name
  secret_mount_path = local.secret_mount_path
  log_volume_name   = docker_volume.application_logs.name
  postgres_user     = var.postgres_user
  postgres_database = var.postgres_database
  postgres_image    = module.local.postgres_image
  grafana_user      = var.grafana_user

  depends_on = [module.local]
}

output "urls" {
  value = {
    application = "http://127.0.0.1:4000"
    grafana     = "http://127.0.0.1:3000"
    pgadmin     = "http://127.0.0.1:5050"
    prometheus  = "http://127.0.0.1:9090"
  }
}
