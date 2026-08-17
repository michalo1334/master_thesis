locals {
  config_path = abspath("${path.module}/config")
  container_ports = {
    alloy   = [{ external = 12345, internal = 12345, ip = "127.0.0.1" }]
    grafana = [{ external = 3000, internal = 3000, ip = "127.0.0.1" }]
    loki    = [{ external = 3100, internal = 3100, ip = "127.0.0.1" }]
    otel_collector = [
      { external = 4317, internal = 4317, ip = "127.0.0.1" },
      { external = 4318, internal = 4318, ip = "127.0.0.1" },
      { external = 8888, internal = 8888, ip = "127.0.0.1" },
      { external = 8889, internal = 8889, ip = "127.0.0.1" }
    ]
    prometheus = [{ external = 9090, internal = 9090, ip = "127.0.0.1" }]
    tempo      = [{ external = 3200, internal = 3200, ip = "127.0.0.1" }]
  }
  container_volumes = {
    alloy = [
      { container_path = "/etc/alloy/config.alloy", host_path = "${local.config_path}/alloy-config.alloy", read_only = true },
      { container_path = "/var/log/network_defense", read_only = true, volume_name = var.log_volume_name },
      { container_path = "/var/lib/alloy/data", volume_name = docker_volume.data["alloy"].name }
    ]
    cadvisor = [
      { container_path = "/rootfs", host_path = "/", read_only = true },
      { container_path = "/var/run", host_path = "/var/run", read_only = true },
      { container_path = "/sys", host_path = "/sys", read_only = true },
      { container_path = "/var/lib/docker", host_path = "/var/lib/docker", read_only = true },
      { container_path = "/dev/disk", host_path = "/dev/disk", read_only = true }
    ]
    grafana = [
      { container_path = "/var/lib/grafana", volume_name = docker_volume.data["grafana"].name },
      { container_path = "/etc/grafana/provisioning", host_path = "${local.config_path}/grafana-provisioning", read_only = true },
      { container_path = "/var/lib/grafana/dashboards", host_path = "${local.config_path}/grafana-dashboards", read_only = true },
      { container_path = "/run/secrets", host_path = var.secret_mount_path, read_only = true }
    ]
    loki = [
      { container_path = "/etc/loki/loki-config.yaml", host_path = "${local.config_path}/loki-config.yaml", read_only = true },
      { container_path = "/loki", volume_name = docker_volume.data["loki"].name }
    ]
    node_exporter = [
      { container_path = "/host", host_path = "/", read_only = true },
      { container_path = "/host/proc", host_path = "/proc", read_only = true },
      { container_path = "/host/sys", host_path = "/sys", read_only = true }
    ]
    otel_collector = [
      { container_path = "/etc/otelcol/config.yaml", host_path = "${local.config_path}/otel-collector-config.yaml", read_only = true }
    ]
    postgres_exporter = [
      { container_path = "/etc/postgres-exporter/postgres-exporter.yaml", host_path = "${local.config_path}/postgres-exporter.yaml", read_only = true },
      { container_path = "/run/secrets", host_path = var.secret_mount_path, read_only = true }
    ]
    postgres_exporter_init = [
      { container_path = "/usr/local/bin/postgres-exporter-init.sh", host_path = "${local.config_path}/postgres-exporter-init.sh", read_only = true },
      { container_path = "/run/secrets", host_path = var.secret_mount_path, read_only = true }
    ]
    prometheus = [
      { container_path = "/etc/prometheus/prometheus.yaml", host_path = "${local.config_path}/prometheus.yaml", read_only = true },
      { container_path = "/prometheus", volume_name = docker_volume.data["prometheus"].name }
    ]
    tempo = [
      { container_path = "/etc/tempo.yaml", host_path = "${local.config_path}/tempo.yaml", read_only = true },
      { container_path = "/var/tempo", volume_name = docker_volume.data["tempo"].name }
    ]
  }
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
}
