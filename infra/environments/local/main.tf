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

module "app" {
  source = "../../modules/local/app"

  app               = local.app
  app_source_path   = abspath("${path.module}/../../../src")
  log_volume_name   = docker_volume.application_logs.name
  name_prefix       = local.name_prefix
  network_name      = docker_network.stack.name
  secret_mount_path = local.secret_mount_path

  depends_on = [module.database]
}

module "database" {
  source = "../../modules/local/database"

  name_prefix       = local.name_prefix
  network_name      = docker_network.stack.name
  pgadmin_email     = var.pgadmin_email
  postgres_database = var.postgres_database
  postgres_user     = var.postgres_user
  secret_mount_path = local.secret_mount_path
}

module "observability" {
  source = "../../modules/local/observability"

  grafana_user      = var.grafana_user
  log_volume_name   = docker_volume.application_logs.name
  name_prefix       = local.name_prefix
  network_name      = docker_network.stack.name
  postgres_database = var.postgres_database
  postgres_host     = local.postgres_host
  postgres_image    = module.database.postgres_image
  postgres_port     = local.postgres_port
  postgres_user     = var.postgres_user
  secret_mount_path = local.secret_mount_path

  depends_on = [module.database]
}
