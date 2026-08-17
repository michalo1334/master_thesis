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
    "PGADMIN_CONFIG_UPGRADE_CHECK_ENABLED=False",
    "PGADMIN_SERVER_JSON_FILE=/pgadmin4/servers.json",
    "PGADMIN_REPLACE_SERVERS_ON_STARTUP=True",
    "PGPASS_FILE=/pgpass/pgpass"
  ]

  upload {
    file    = "/pgadmin4/servers.json"
    content = jsonencode({
      Servers = {
        "1" = {
          Name          = var.postgres_database
          Group         = "Servers"
          Host          = local.postgres_host
          Port          = local.postgres_ports[0].internal
          MaintenanceDB = var.postgres_database
          Username      = var.postgres_user
          SSLMode       = "prefer"
          PassFile      = "/var/lib/pgadmin/.pgpass"
          Comment       = "Auto-registered from Terraform (local)"
        }
      }
    })
  }

  upload {
    file        = "/pgpass/pgpass"
    content     = "${local.postgres_host}:${local.postgres_ports[0].internal}:${var.postgres_database}:${var.postgres_user}:${chomp(file("${var.secret_mount_path}/postgres-password"))}\n"
    permissions = "0600"
  }

  entrypoint = ["/bin/sh", "-c", <<-EOT
    set -eu
    PGPASS_USER_FILE="/var/lib/pgadmin/.pgpass"
    # Keep pgpass in sync on every start (entrypoint.sh copies it only on first DB init).
    if [ -f "/pgpass/pgpass" ]; then
      cp /pgpass/pgpass "$PGPASS_USER_FILE"
      chmod 600 "$PGPASS_USER_FILE"
      chown 5050:5050 "$PGPASS_USER_FILE" 2>/dev/null || true
    fi
    exec /entrypoint.sh
  EOT
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
