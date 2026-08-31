resource "docker_image" "stack" {
  for_each = local.images

  name = each.value
}

resource "docker_volume" "data" {
  for_each = toset(["alloy", "grafana", "loki", "prometheus", "tempo"])

  name = "${var.name_prefix}-${each.key}-data"
}

resource "docker_container" "alloy" {
  image = docker_image.stack["alloy"].image_id
  name  = "${var.name_prefix}-alloy"

  command = [
    "run",
    "--server.http.listen-addr=0.0.0.0:12345",
    "--storage.path=/var/lib/alloy/data",
    "/etc/alloy/config.alloy"
  ]

  networks_advanced {
    aliases = ["alloy"]
    name    = var.observability_network
  }

  upload {
    content = local.alloy_config
    file    = "/etc/alloy/config.alloy"
  }

  dynamic "volumes" {
    for_each = local.container_volumes.alloy
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "10s"
    test         = ["CMD", "/bin/alloy", "fmt", "/etc/alloy/config.alloy"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "cadvisor" {
  image      = docker_image.stack["cadvisor"].image_id
  name       = "${var.name_prefix}-cadvisor"
  privileged = true

  networks_advanced {
    aliases = ["cadvisor"]
    name    = var.observability_network
  }

  devices {
    container_path = "/dev/kmsg"
    host_path      = "/dev/kmsg"
    permissions    = "rwm"
  }

  dynamic "volumes" {
    for_each = local.container_volumes.cadvisor
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "10s"
    test         = ["CMD-SHELL", "wget --quiet --tries=1 --spider $${CADVISOR_HEALTHCHECK_URL} || exit 1"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "grafana" {
  depends_on = [
    docker_container.alloy,
    docker_container.loki,
    docker_container.prometheus,
    docker_container.tempo
  ]

  image = docker_image.stack["grafana"].image_id
  name  = "${var.name_prefix}-grafana"
  user  = "0"

  env = [
    "GF_SECURITY_ADMIN_USER=${var.grafana_admin_user}",
    "GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana-admin-password",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_AUTH_ANONYMOUS_ENABLED=false"
  ]

  networks_advanced {
    aliases = ["grafana"]
    name    = var.observability_network
  }

  ports {
    external = var.grafana_host_port
    internal = 3000
    ip       = "127.0.0.1"
  }

  dynamic "volumes" {
    for_each = local.container_volumes.grafana
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "20s"
    test         = ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:3000/api/health || exit 1"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "loki" {
  image   = docker_image.stack["loki"].image_id
  name    = "${var.name_prefix}-loki"
  command = ["-config.file=/etc/loki/loki-config.yaml"]
  user    = "0:0"

  networks_advanced {
    aliases = ["loki"]
    name    = var.observability_network
  }

  dynamic "volumes" {
    for_each = local.container_volumes.loki
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "20s"
    test         = ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:3100/ready || exit 1"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "node_exporter" {
  image = docker_image.stack["node_exporter"].image_id
  name  = "${var.name_prefix}-node-exporter"

  command = [
    "--path.rootfs=/host",
    "--path.procfs=/host/proc",
    "--path.sysfs=/host/sys",
    "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
  ]

  networks_advanced {
    aliases = ["node-exporter"]
    name    = var.observability_network
  }

  dynamic "volumes" {
    for_each = local.container_volumes.node_exporter
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "10s"
    test         = ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:9100/metrics || exit 1"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "postgres_exporter_init" {
  attach   = true
  command  = ["/bin/sh", "/usr/local/bin/postgres-exporter-init.sh"]
  image    = var.postgres_image
  must_run = false
  name     = "${var.name_prefix}-postgres-exporter-init"
  wait     = false

  env = [
    "PGHOST=${var.postgres_host}",
    "PGPORT=${var.postgres_port}",
    "PGDATABASE=${var.database.name}",
    "PGUSER=${var.database.user}"
  ]

  networks_advanced {
    name = var.observability_network
  }

  dynamic "volumes" {
    for_each = local.container_volumes.postgres_exporter_init
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  lifecycle {
    postcondition {
      condition     = self.exit_code == 0
      error_message = "The PostgreSQL exporter setup container must exit successfully."
    }
  }
}

resource "docker_container" "postgres_exporter" {
  depends_on = [docker_container.postgres_exporter_init]

  image = docker_image.stack["postgres_exporter"].image_id
  name  = "${var.name_prefix}-postgres-exporter"
  user  = "0"

  command = [
    "--collector.long_running_transactions",
    "--config.file=/etc/postgres-exporter/postgres-exporter.yaml"
  ]

  env = [
    "DATA_SOURCE_URI=${var.postgres_host}:${var.postgres_port}/${var.database.name}?sslmode=disable",
    "DATA_SOURCE_USER=postgres_exporter",
    "DATA_SOURCE_PASS_FILE=/run/secrets/postgres-exporter-password"
  ]

  networks_advanced {
    aliases = ["postgres-exporter"]
    name    = var.observability_network
  }

  dynamic "volumes" {
    for_each = local.container_volumes.postgres_exporter
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "20s"
    test         = ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:9187/metrics || exit 1"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "prometheus" {
  image = docker_image.stack["prometheus"].image_id
  name  = "${var.name_prefix}-prometheus"

  command = [
    "--config.file=/etc/prometheus/prometheus.yaml",
    "--storage.tsdb.retention.time=7d",
    "--web.enable-lifecycle"
  ]

  networks_advanced {
    aliases = ["prometheus"]
    name    = var.observability_network
  }

  ports {
    external = var.prometheus_host_port
    internal = 9090
    ip       = "127.0.0.1"
  }

  upload {
    content = local.prometheus_config
    file    = "/etc/prometheus/prometheus.yaml"
  }

  dynamic "volumes" {
    for_each = local.container_volumes.prometheus
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "20s"
    test         = ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:9090/-/ready || exit 1"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "site_collector" {
  for_each = var.sites

  command = ["--config=/etc/otelcol/config.yaml"]
  image   = docker_image.stack["otel_collector"].image_id
  name    = "${var.name_prefix}-otel-collector-${each.key}"

  networks_advanced {
    aliases = ["otel-collector"]
    name    = var.site_networks[each.key]
  }

  networks_advanced {
    aliases = ["otel-collector-${each.key}"]
    name    = var.observability_network
  }

  upload {
    content = local.collector_configs[each.key]
    file    = "/etc/otelcol/config.yaml"
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "10s"
    test         = ["CMD", "/otelcol-contrib", "validate", "--config=file:/etc/otelcol/config.yaml"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "tempo" {
  image   = docker_image.stack["tempo"].image_id
  name    = "${var.name_prefix}-tempo"
  command = ["-config.file=/etc/tempo.yaml"]

  networks_advanced {
    aliases = ["tempo"]
    name    = var.observability_network
  }

  dynamic "volumes" {
    for_each = local.container_volumes.tempo
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "20s"
    test         = ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:3200/ready || exit 1"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}
