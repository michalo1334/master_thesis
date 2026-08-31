locals {
  config_path  = abspath("${path.module}/config")
  alloy_config = templatefile("${local.config_path}/alloy-config.alloy", { service_name = var.service_name })
  prometheus_config = templatefile("${local.config_path}/prometheus.yaml.tftpl", {
    service_name = var.service_name
    sites        = var.sites
  })

  collector_configs = {
    for site, _ in var.sites : site => templatefile("${local.config_path}/site-collector.yaml.tftpl", {
      targets = [
        for key, node in var.nodes : {
          endpoint = "app-${node.index}:4001"
          site     = site
          provider = var.sites[site].provider
          region   = var.sites[site].region
          instance = var.sites[site].instance
          replica  = "app-${site}-${node.index}"
        }
        if node.site == site
      ]
    })
  }

  container_volumes = {
    alloy = [
      { container_path = "/var/log/${var.service_name}", read_only = true, volume_name = var.log_volume_name },
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
      { container_path = "/etc/grafana/provisioning/datasources", host_path = "${local.config_path}/grafana-provisioning/datasources", read_only = true },
      { container_path = "/run/secrets/grafana-admin-password", host_path = "${var.secret_mount_path}/grafana-admin-password", read_only = true }
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
    postgres_exporter = [
      { container_path = "/etc/postgres-exporter/postgres-exporter.yaml", host_path = "${local.config_path}/postgres-exporter.yaml", read_only = true },
      { container_path = "/run/secrets/postgres-exporter-password", host_path = "${var.secret_mount_path}/postgres-exporter-password", read_only = true }
    ]
    postgres_exporter_init = [
      { container_path = "/usr/local/bin/postgres-exporter-init.sh", host_path = "${local.config_path}/postgres-exporter-init.sh", read_only = true },
      { container_path = "/run/secrets/postgres-password", host_path = "${var.secret_mount_path}/postgres-password", read_only = true },
      { container_path = "/run/secrets/postgres-exporter-password", host_path = "${var.secret_mount_path}/postgres-exporter-password", read_only = true }
    ]
    prometheus = [
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
