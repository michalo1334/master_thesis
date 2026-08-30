module "deployment_config" {
  source = "../../modules/common/deployment_config"

  deployment = var.deployment
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

    precondition {
      condition     = local.all_host_ports == local.legacy_host_ports
      error_message = "State 01 preserves the legacy fixed host ports until their modules consume the component configuration."
    }
  }
}

check "host_ports_valid" {
  assert {
    condition     = alltrue([for port in local.all_host_ports : port >= 1 && port <= 65535])
    error_message = "Every host entry port must be between 1 and 65535."
  }

  assert {
    condition     = length(local.all_host_ports) == length(distinct(local.all_host_ports))
    error_message = "All eight configured host entry ports must be pairwise unique."
  }
}

resource "docker_volume" "application_logs" {
  name = "${local.name_prefix}-logs"
}

module "analysis" {
  source = "../../modules/local/analysis"

  analysis_source_path = abspath("${path.module}/../../../evaluation/analysis")
  name_prefix          = local.name_prefix
  network_name         = docker_network.stack.name
}

module "redis" {
  count  = local.pubsub_adapter == "redis" ? 1 : 0
  source = "../../modules/local/redis"

  name_prefix   = local.name_prefix
  network_name  = docker_network.stack.name
  password_file = "${local.secret_mount_path}/redis-password"
}

module "app" {
  source = "../../modules/local/app"

  app               = local.app
  app_replicas      = local.app_replicas
  app_source_path   = abspath("${path.module}/../../../src")
  log_volume_name   = docker_volume.application_logs.name
  name_prefix       = local.name_prefix
  network_name      = docker_network.stack.name
  pubsub_adapter    = local.pubsub_adapter
  secret_mount_path = local.secret_mount_path

  depends_on = [module.analysis, module.database, module.redis]
}

module "database" {
  source = "../../modules/local/database"

  name_prefix       = local.name_prefix
  network_name      = docker_network.stack.name
  pgadmin_email     = var.pgadmin.admin_email
  postgres_database = local.database_cfg.name
  postgres_user     = local.database_cfg.user
  secret_mount_path = local.secret_mount_path
}
