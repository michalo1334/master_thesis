locals {
  app_secret_files = [
    "live-view-signing-salt",
    "postgres-password",
    "rabbitmq-password",
    "secret-key-base"
  ]
  application    = module.deployment_config.application
  database       = module.deployment_config.database
  name_prefix    = module.deployment_config.config.name
  nodes          = module.deployment_config.nodes
  pubsub_adapter = module.deployment_config.pubsub.adapter
  rabbitmq       = merge(module.deployment_config.rabbitmq, { host = "rabbitmq" })
  required_secret_files = concat([
    "grafana-admin-password",
    "pgadmin-password",
    "postgres-exporter-password",
    ], local.app_secret_files, [
    for site in keys(module.deployment_config.sites) : "erlang-cookies/${site}/.erlang.cookie"
  ], local.pubsub_adapter == "redis" ? ["redis-password"] : [])
  secret_mount_path = abspath(var.secrets.directory)
  sites             = module.deployment_config.sites
}
