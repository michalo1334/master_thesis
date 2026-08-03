terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

resource "docker_image" "postgres" {
  name = "postgres:18"
}

resource "docker_image" "pgadmin" {
  name = "dpage/pgadmin4:9.12"
}

resource "docker_volume" "postgres_data" {
  name = "${var.name_prefix}-postgres-data"
}

resource "docker_volume" "pgadmin_data" {
  name = "${var.name_prefix}-pgadmin-data"
}

locals {
  postgres_ports = [{ internal = 5432, external = 5433, ip = "127.0.0.1" }]
  pgadmin_ports  = [{ internal = 80, external = 5050, ip = "127.0.0.1" }]
  postgres_volumes = [
    { volume_name = docker_volume.postgres_data.name, container_path = "/var/lib/postgresql" },
    { host_path = var.secret_mount_path, container_path = "/run/secrets", read_only = true }
  ]
  pgadmin_volumes = [
    { volume_name = docker_volume.pgadmin_data.name, container_path = "/var/lib/pgadmin" },
    { host_path = var.secret_mount_path, container_path = "/run/secrets", read_only = true }
  ]
}

resource "docker_container" "postgres" {
  name  = "${var.name_prefix}-postgres"
  image = docker_image.postgres.image_id

  env = [
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_DB=${var.postgres_database}",
    "POSTGRES_PASSWORD_FILE=/run/secrets/postgres-password"
  ]

  networks_advanced {
    name    = var.network_name
    aliases = ["postgres"]
  }

  dynamic "ports" {
    for_each = local.postgres_ports
    iterator = port

    content {
      internal = port.value.internal
      external = port.value.external
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.postgres_volumes
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
    interval     = "5s"
    timeout      = "3s"
    retries      = 10
    start_period = "20s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "pgadmin" {
  name  = "${var.name_prefix}-pgadmin"
  image = docker_image.pgadmin.image_id
  user  = "0"

  env = [
    "PGADMIN_DEFAULT_EMAIL=${var.pgadmin_email}",
    "PGADMIN_DEFAULT_PASSWORD_FILE=/run/secrets/pgadmin-password",
    "PGADMIN_CONFIG_SERVER_MODE=False",
    "PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False",
    "PGADMIN_CONFIG_UPGRADE_CHECK_ENABLED=False"
  ]

  networks_advanced {
    name    = var.network_name
    aliases = ["pgadmin"]
  }

  dynamic "ports" {
    for_each = local.pgadmin_ports
    iterator = port

    content {
      internal = port.value.internal
      external = port.value.external
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.pgadmin_volumes
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost/misc/ping || exit 1"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 6
    start_period = "20s"
  }

  restart = "unless-stopped"
  wait    = true
}

output "postgres_image" {
  value = docker_image.postgres.image_id
}
