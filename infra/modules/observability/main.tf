terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  images = {
    alloy             = "grafana/alloy:v1.17.1"
    cadvisor          = "gcr.io/cadvisor/cadvisor:v0.49.2"
    grafana           = "grafana/grafana:11.2.0"
    loki              = "grafana/loki:3.3.2"
    node_exporter     = "quay.io/prometheus/node-exporter:v1.9.1"
    otel_collector    = "otel/opentelemetry-collector-contrib:0.111.0"
    postgres_exporter = "quay.io/prometheuscommunity/postgres-exporter:v0.17.1"
    prometheus        = "prom/prometheus:v2.55.0"
    tempo             = "grafana/tempo:2.5.0"
  }
  container_ports = {
    otel_collector = [
      { internal = 4317, external = 4317, ip = "127.0.0.1" },
      { internal = 4318, external = 4318, ip = "127.0.0.1" },
      { internal = 8888, external = 8888, ip = "127.0.0.1" },
      { internal = 8889, external = 8889, ip = "127.0.0.1" }
    ]
    tempo      = [{ internal = 3200, external = 3200, ip = "127.0.0.1" }]
    prometheus = [{ internal = 9090, external = 9090, ip = "127.0.0.1" }]
    loki       = [{ internal = 3100, external = 3100, ip = "127.0.0.1" }]
    alloy      = [{ internal = 12345, external = 12345, ip = "127.0.0.1" }]
    grafana    = [{ internal = 3000, external = 3000, ip = "127.0.0.1" }]
  }
  container_volumes = {
    otel_collector = [
      { host_path = "${var.config_path}/otel-collector-config.yaml", container_path = "/etc/otelcol/config.yaml", read_only = true }
    ]
    tempo = [
      { host_path = "${var.config_path}/tempo.yaml", container_path = "/etc/tempo.yaml", read_only = true },
      { volume_name = docker_volume.data["tempo"].name, container_path = "/var/tempo" }
    ]
    prometheus = [
      { host_path = "${var.config_path}/prometheus.yaml", container_path = "/etc/prometheus/prometheus.yaml", read_only = true },
      { volume_name = docker_volume.data["prometheus"].name, container_path = "/prometheus" }
    ]
    node_exporter = [
      { host_path = "/", container_path = "/host", read_only = true },
      { host_path = "/proc", container_path = "/host/proc", read_only = true },
      { host_path = "/sys", container_path = "/host/sys", read_only = true }
    ]
    cadvisor = [
      { host_path = "/", container_path = "/rootfs", read_only = true },
      { host_path = "/var/run", container_path = "/var/run", read_only = true },
      { host_path = "/sys", container_path = "/sys", read_only = true },
      { host_path = "/var/lib/docker", container_path = "/var/lib/docker", read_only = true },
      { host_path = "/dev/disk", container_path = "/dev/disk", read_only = true }
    ]
    postgres_exporter_init = [
      { host_path = "${var.config_path}/postgres-exporter-init.sh", container_path = "/usr/local/bin/postgres-exporter-init.sh", read_only = true },
      { host_path = var.secret_mount_path, container_path = "/run/secrets", read_only = true }
    ]
    postgres_exporter = [
      { host_path = "${var.config_path}/postgres-exporter.yaml", container_path = "/etc/postgres-exporter/postgres-exporter.yaml", read_only = true },
      { host_path = var.secret_mount_path, container_path = "/run/secrets", read_only = true }
    ]
    loki = [
      { host_path = "${var.config_path}/loki-config.yaml", container_path = "/etc/loki/loki-config.yaml", read_only = true },
      { volume_name = docker_volume.data["loki"].name, container_path = "/loki" }
    ]
    alloy = [
      { host_path = "${var.config_path}/alloy-config.alloy", container_path = "/etc/alloy/config.alloy", read_only = true },
      { volume_name = var.log_volume_name, container_path = "/var/log/network_defense", read_only = true },
      { volume_name = docker_volume.data["alloy"].name, container_path = "/var/lib/alloy/data" }
    ]
    grafana = [
      { volume_name = docker_volume.data["grafana"].name, container_path = "/var/lib/grafana" },
      { host_path = "${var.config_path}/grafana-provisioning", container_path = "/etc/grafana/provisioning", read_only = true },
      { host_path = "${var.config_path}/grafana-dashboards", container_path = "/var/lib/grafana/dashboards", read_only = true },
      { host_path = var.secret_mount_path, container_path = "/run/secrets", read_only = true }
    ]
  }
}

resource "docker_image" "stack" {
  for_each = local.images

  name = each.value
}

resource "docker_volume" "data" {
  for_each = toset(["alloy", "grafana", "loki", "prometheus", "tempo"])

  name = "${var.name_prefix}-${each.key}-data"
}

resource "docker_container" "otel_collector" {
  name    = "${var.name_prefix}-otel-collector"
  image   = docker_image.stack["otel_collector"].image_id
  command = ["--config=/etc/otelcol/config.yaml"]

  networks_advanced {
    name    = var.network_name
    aliases = ["otel-collector"]
  }

  dynamic "ports" {
    for_each = local.container_ports.otel_collector
    iterator = port

    content {
      internal = port.value.internal
      external = port.value.external
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.container_volumes.otel_collector
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  restart = "unless-stopped"
}

resource "docker_container" "tempo" {
  name    = "${var.name_prefix}-tempo"
  image   = docker_image.stack["tempo"].image_id
  command = ["-config.file=/etc/tempo.yaml"]

  networks_advanced {
    name    = var.network_name
    aliases = ["tempo"]
  }

  dynamic "ports" {
    for_each = local.container_ports.tempo
    iterator = port

    content {
      internal = port.value.internal
      external = port.value.external
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.container_volumes.tempo
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  restart = "unless-stopped"
}

resource "docker_container" "prometheus" {
  name  = "${var.name_prefix}-prometheus"
  image = docker_image.stack["prometheus"].image_id
  command = [
    "--config.file=/etc/prometheus/prometheus.yaml",
    "--storage.tsdb.retention.time=7d",
    "--web.enable-lifecycle"
  ]

  networks_advanced {
    name    = var.network_name
    aliases = ["prometheus"]
  }

  dynamic "ports" {
    for_each = local.container_ports.prometheus
    iterator = port

    content {
      internal = port.value.internal
      external = port.value.external
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.container_volumes.prometheus
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  restart = "unless-stopped"
}

resource "docker_container" "node_exporter" {
  name  = "${var.name_prefix}-node-exporter"
  image = docker_image.stack["node_exporter"].image_id
  command = [
    "--path.rootfs=/host",
    "--path.procfs=/host/proc",
    "--path.sysfs=/host/sys",
    "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
  ]

  networks_advanced {
    name    = var.network_name
    aliases = ["node-exporter"]
  }

  dynamic "volumes" {
    for_each = local.container_volumes.node_exporter
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  restart = "unless-stopped"
}

resource "docker_container" "cadvisor" {
  name       = "${var.name_prefix}-cadvisor"
  image      = docker_image.stack["cadvisor"].image_id
  privileged = true

  networks_advanced {
    name    = var.network_name
    aliases = ["cadvisor"]
  }

  devices {
    host_path      = "/dev/kmsg"
    container_path = "/dev/kmsg"
    permissions    = "rwm"
  }

  dynamic "volumes" {
    for_each = local.container_volumes.cadvisor
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  restart = "unless-stopped"
}

resource "docker_container" "postgres_exporter_init" {
  name     = "${var.name_prefix}-postgres-exporter-init"
  image    = var.postgres_image
  command  = ["/bin/sh", "/usr/local/bin/postgres-exporter-init.sh"]
  attach   = true
  must_run = false

  env = [
    "PGHOST=postgres",
    "PGPORT=5432",
    "PGDATABASE=${var.postgres_database}",
    "PGUSER=${var.postgres_user}"
  ]

  networks_advanced {
    name = var.network_name
  }

  dynamic "volumes" {
    for_each = local.container_volumes.postgres_exporter_init
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }
}

resource "docker_container" "postgres_exporter" {
  name  = "${var.name_prefix}-postgres-exporter"
  image = docker_image.stack["postgres_exporter"].image_id
  user  = "0"
  command = [
    "--collector.long_running_transactions",
    "--config.file=/etc/postgres-exporter/postgres-exporter.yaml"
  ]

  env = [
    "DATA_SOURCE_URI=postgres:5432/${var.postgres_database}?sslmode=disable",
    "DATA_SOURCE_USER=postgres_exporter",
    "DATA_SOURCE_PASS_FILE=/run/secrets/postgres-exporter-password"
  ]

  networks_advanced {
    name    = var.network_name
    aliases = ["postgres-exporter"]
  }

  dynamic "volumes" {
    for_each = local.container_volumes.postgres_exporter
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  depends_on = [docker_container.postgres_exporter_init]
  restart    = "unless-stopped"
}

resource "docker_container" "loki" {
  name    = "${var.name_prefix}-loki"
  image   = docker_image.stack["loki"].image_id
  command = ["-config.file=/etc/loki/loki-config.yaml"]
  user    = "0:0"

  networks_advanced {
    name    = var.network_name
    aliases = ["loki"]
  }

  dynamic "ports" {
    for_each = local.container_ports.loki
    iterator = port

    content {
      internal = port.value.internal
      external = port.value.external
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.container_volumes.loki
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  restart = "unless-stopped"
}

resource "docker_container" "alloy" {
  name  = "${var.name_prefix}-alloy"
  image = docker_image.stack["alloy"].image_id
  command = [
    "run",
    "--server.http.listen-addr=0.0.0.0:12345",
    "--storage.path=/var/lib/alloy/data",
    "/etc/alloy/config.alloy"
  ]

  networks_advanced {
    name    = var.network_name
    aliases = ["alloy"]
  }

  dynamic "ports" {
    for_each = local.container_ports.alloy
    iterator = port

    content {
      internal = port.value.internal
      external = port.value.external
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.container_volumes.alloy
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  restart = "unless-stopped"
}

resource "docker_container" "grafana" {
  name  = "${var.name_prefix}-grafana"
  image = docker_image.stack["grafana"].image_id
  user  = "0"

  env = [
    "GF_SECURITY_ADMIN_USER=${var.grafana_user}",
    "GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana-admin-password",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_AUTH_ANONYMOUS_ENABLED=false"
  ]

  networks_advanced {
    name    = var.network_name
    aliases = ["grafana"]
  }

  dynamic "ports" {
    for_each = local.container_ports.grafana
    iterator = port

    content {
      internal = port.value.internal
      external = port.value.external
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.container_volumes.grafana
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  depends_on = [
    docker_container.tempo,
    docker_container.prometheus,
    docker_container.loki,
    docker_container.alloy
  ]

  healthcheck {
    test         = ["CMD-SHELL", "curl -fsS http://localhost:3000/api/health || exit 1"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 6
    start_period = "20s"
  }

  restart = "unless-stopped"
  wait    = true
}
