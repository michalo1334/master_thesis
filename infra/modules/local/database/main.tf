resource "docker_image" "pgadmin" {
  name = "dpage/pgadmin4:9.12"
}

resource "docker_image" "postgres" {
  name = "postgres:18"
}

resource "docker_volume" "pgadmin_data" {
  name = "${var.name_prefix}-pgadmin-data"
}

resource "docker_volume" "postgres_data" {
  name = "${var.name_prefix}-postgres-data"
}

resource "docker_container" "pgadmin" {
  image = docker_image.pgadmin.image_id
  name  = "${var.name_prefix}-pgadmin"
  user  = "0"

  env = [
    "PGADMIN_DEFAULT_EMAIL=${var.pgadmin_email}",
    "PGADMIN_DEFAULT_PASSWORD_FILE=/run/secrets/pgadmin-password",
    "PGADMIN_CONFIG_SERVER_MODE=False",
    "PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False",
    "PGADMIN_CONFIG_UPGRADE_CHECK_ENABLED=False"
  ]

  networks_advanced {
    aliases = ["pgadmin"]
    name    = var.network_name
  }

  dynamic "ports" {
    for_each = local.pgadmin_ports
    iterator = port

    content {
      external = port.value.external
      internal = port.value.internal
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.pgadmin_volumes
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
    test         = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost/misc/ping || exit 1"]
    timeout      = "5s"
  }

  restart = "unless-stopped"
  wait    = true
}

resource "docker_container" "postgres" {
  image = docker_image.postgres.image_id
  name  = "${var.name_prefix}-postgres"

  env = [
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_DB=${var.postgres_database}",
    "POSTGRES_PASSWORD_FILE=/run/secrets/postgres-password"
  ]

  networks_advanced {
    aliases = [local.postgres_host]
    name    = var.network_name
  }

  dynamic "ports" {
    for_each = local.postgres_ports
    iterator = port

    content {
      external = port.value.external
      internal = port.value.internal
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.postgres_volumes
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }

  healthcheck {
    interval     = "5s"
    retries      = 10
    start_period = "20s"
    test         = ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
    timeout      = "3s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}
