module "deployment_config" {
  source = "../../modules/common/deployment_config"

  deployment = var.deployment
}

resource "docker_network" "site" {
  for_each = module.deployment_config.sites

  name = "${local.name_prefix}-${each.key}-network"

  lifecycle {
    precondition {
      condition = alltrue([
        for filename in local.required_secret_files : fileexists("${local.secret_mount_path}/${filename}")
      ])
      error_message = "Secret directory must contain: ${join(", ", local.required_secret_files)}."
    }

    precondition {
      condition     = local.inactive_host_ports == local.legacy_host_ports
      error_message = "State 05 preserves the legacy Grafana and Prometheus host ports until their modules consume the component configuration."
    }
  }
}

resource "docker_network" "observability" {
  name = "${local.name_prefix}-observability"
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
  site_networks        = { for site, network in docker_network.site : site => network.name }
  sites                = module.deployment_config.sites
}

module "redis" {
  count  = local.pubsub_adapter == "redis" ? 1 : 0
  source = "../../modules/local/redis"

  name_prefix   = local.name_prefix
  site_networks = { for site, network in docker_network.site : site => network.name }
  password_file = "${local.secret_mount_path}/redis-password"
}

module "app" {
  source = "../../modules/local/app"

  adapter                = local.pubsub_adapter
  analysis_max_zip_bytes = module.analysis.max_response_size
  app_source_path        = abspath("${path.module}/../../../src")
  application            = local.application
  database               = local.database
  database_host          = module.database.postgres_host
  database_port          = module.database.postgres_port
  host                   = var.application.host
  host_ports             = var.application.host_ports
  log_level              = var.application.log_level
  log_volume_name        = docker_volume.application_logs.name
  name_prefix            = local.name_prefix
  nodes                  = local.nodes
  secret_mount_path      = local.secret_mount_path
  service_name           = local.application.service_name
  site_networks          = { for site, network in docker_network.site : site => network.name }
  sites                  = local.sites

  depends_on = [module.analysis, module.database, module.redis]
}

module "database" {
  source = "../../modules/local/database"

  name_prefix        = local.name_prefix
  observability_name = docker_network.observability.name
  pgadmin_email      = var.pgadmin.admin_email
  pgadmin_host_port  = var.pgadmin.host_port
  postgres_database  = local.database.name
  postgres_host_port = var.database.host_port
  postgres_user      = local.database.user
  secret_mount_path  = local.secret_mount_path
  site_networks      = { for site, network in docker_network.site : site => network.name }
}
