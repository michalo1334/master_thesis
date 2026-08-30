locals {
  nodes = {
    for key, node in var.nodes : key => merge(node, {
      role     = node.site == var.application.primary_site && node.index == 0 ? "coordinator" : "worker"
      provider = var.sites[node.site].provider
      region   = var.sites[node.site].region
      instance = var.sites[node.site].instance
    })
  }

  dev_host_ports = [
    { external = var.host_ports.http, internal = 4000 },
    { external = var.host_ports.metrics, internal = 4001 },
    { external = var.host_ports.assets, internal = 5173 },
    { external = var.host_ports.debugger, internal = 9229 }
  ]

  dev_mounts = [
    { container_path = "/app/lib", host_path = "${var.app_source_path}/lib" },
    { container_path = "/app/priv", host_path = "${var.app_source_path}/priv" },
    { container_path = "/app/test", host_path = "${var.app_source_path}/test" },
    { container_path = "/app/config", host_path = "${var.app_source_path}/config" },
    { container_path = "/app/assets/js", host_path = "${var.app_source_path}/assets/js" },
    { container_path = "/app/assets/css", host_path = "${var.app_source_path}/assets/css" },
    { container_path = "/app/assets/svelte", host_path = "${var.app_source_path}/assets/svelte" },
    { container_path = "/app/assets/vite.config.mjs", host_path = "${var.app_source_path}/assets/vite.config.mjs" },
    { container_path = "/app/_build_docker", volume_name = docker_volume.build.name },
    { container_path = "/app/deps", volume_name = docker_volume.dependencies.name }
  ]

  setup_environment = [
    "REPO_HOSTNAME=${var.database_host}",
    "REPO_PORT=${var.database_port}",
    "REPO_USERNAME=${var.database.user}",
    "REPO_DATABASE=${var.database.name}",
    "REPO_PASSWORD_FILE=/run/secrets/postgres-password"
  ]

  setup_mounts = concat(local.dev_mounts, [
    { container_path = "/run/secrets/postgres-password", host_path = "${var.secret_mount_path}/postgres-password", read_only = true }
  ])

  node_environment = {
    for key, node in local.nodes : key => concat([
      "REPO_HOSTNAME=${var.database_host}",
      "REPO_PORT=${var.database_port}",
      "REPO_USERNAME=${var.database.user}",
      "REPO_DATABASE=${var.database.name}",
      "REPO_PASSWORD_FILE=/run/secrets/postgres-password",
      "SECRET_KEY_BASE_FILE=/run/secrets/secret-key-base",
      "LIVE_VIEW_SIGNING_SALT_FILE=/run/secrets/live-view-signing-salt",
      "PHX_HOST=${var.host}",
      "PHX_IP=0.0.0.0",
      "PORT=4000",
      "MIX_BUILD_PATH=/app/_build_docker",
      "LOG_FILE_LEVEL=${var.log_level}",
      "LOG_FILE_PATH=/var/log/${var.service_name}/app.${node.site}.${node.index}.jsonl",
      "ROLE=${node.role}",
      "PUBSUB_ADAPTER=${var.adapter}",
      "DNS_CLUSTER_QUERY=app",
      "ANALYSIS_SERVICE_URL=http://analysis:8080",
      "ANALYSIS_SERVICE_CONNECT_TIMEOUT_MS=5000",
      "ANALYSIS_SERVICE_TIMEOUT_MS=120000",
      "ANALYSIS_SERVICE_MAX_ZIP_BYTES=${var.analysis_max_zip_bytes}",
      "OTEL_SERVICE_NAME=${var.service_name}",
      "OTEL_RESOURCE_ATTRIBUTES=provider=${node.provider},region=${node.region},instance=${node.instance},site=${node.site},replica=app-${node.site}-${node.index},role=${node.role},service.instance.id=app-${node.site}-${node.index}"
    ], var.adapter == "redis" ? [
      "REDIS_HOST=redis",
      "REDIS_PORT=6379",
      "REDIS_PASSWORD_FILE=/run/secrets/redis-password",
      "PUBSUB_NODE_NAME=${var.service_name}-${node.site}-app-${node.index}"
    ] : [])
  }

  node_mounts = {
    for key, node in local.nodes : key => concat(local.dev_mounts, [
      { container_path = "/var/log/${var.service_name}", volume_name = var.log_volume_name },
      { container_path = "/run/secrets/postgres-password", host_path = "${var.secret_mount_path}/postgres-password", read_only = true },
      { container_path = "/run/secrets/secret-key-base", host_path = "${var.secret_mount_path}/secret-key-base", read_only = true },
      { container_path = "/run/secrets/live-view-signing-salt", host_path = "${var.secret_mount_path}/live-view-signing-salt", read_only = true },
      { container_path = "/run/secrets/erlang-cookie", host_path = "${var.secret_mount_path}/erlang-cookies/${node.site}/.erlang.cookie", read_only = true }
    ], var.adapter == "redis" ? [
      { container_path = "/run/secrets/redis-password", host_path = "${var.secret_mount_path}/redis-password", read_only = true }
    ] : [])
  }
}
