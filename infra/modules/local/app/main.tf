resource "docker_image" "dev" {
  count = var.app.mode == "dev" ? 1 : 0

  name = "${var.name_prefix}-app:dev"

  build {
    context    = var.app_source_path
    dockerfile = "Dockerfile.dev"
  }

  triggers = {
    build_inputs = sha1(join("", [
      for filename in [
        ".dockerignore",
        ".formatter.exs",
        "Dockerfile.dev",
        "mix.exs",
        "mix.lock",
        "package.json",
        "package-lock.json",
        "prettier.config.mjs",
        "config/config.exs",
        "config/dev.exs",
        "config/runtime.exs",
        "lib/network_defense/runtime_config.ex"
      ] : filesha1("${var.app_source_path}/${filename}")
    ]))
  }
}

resource "docker_image" "prod" {
  count = var.app.mode == "prod" ? 1 : 0

  name = var.app.image

  lifecycle {
    precondition {
      condition     = var.app.image != null && var.app.image != ""
      error_message = "app_image is required for prod mode."
    }
  }
}

resource "docker_volume" "build" {
  count = var.app.mode == "dev" ? 1 : 0

  name = "${var.name_prefix}-app-build"
}

resource "docker_volume" "dependencies" {
  count = var.app.mode == "dev" ? 1 : 0

  name = "${var.name_prefix}-app-dependencies"
}

resource "docker_container" "migrate" {
  count = var.app.mode == "prod" ? 1 : 0

  attach   = true
  command  = ["/app/bin/migrate"]
  env      = var.app.environment
  image    = local.image_id
  must_run = false
  name     = "${var.name_prefix}-app-migrate"

  networks_advanced {
    name = var.network_name
  }

  dynamic "volumes" {
    for_each = [{ container_path = "/run/secrets", host_path = var.secret_mount_path, read_only = true }]
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = mount.value.host_path
      read_only      = mount.value.read_only
    }
  }
}

resource "docker_container" "setup" {
  count = var.app.mode == "dev" ? 1 : 0

  attach   = true
  command  = ["sh", "-c", "mix deps.get && mix ecto.migrate && mix run priv/repo/seeds.exs"]
  env      = var.app.environment
  image    = local.image_id
  must_run = false
  name     = "${var.name_prefix}-app-setup"

  networks_advanced {
    name = var.network_name
  }

  dynamic "volumes" {
    for_each = local.volumes
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      read_only      = try(mount.value.read_only, false)
      volume_name    = try(mount.value.volume_name, null)
    }
  }
}

resource "docker_container" "app" {
  depends_on = [docker_container.migrate, docker_container.setup]

  env   = var.app.environment
  image = local.image_id
  name  = "${var.name_prefix}-app"

  networks_advanced {
    aliases = ["network_defense"]
    name    = var.network_name
  }

  dynamic "ports" {
    for_each = local.ports
    iterator = port

    content {
      external = port.value.external
      internal = port.value.internal
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.volumes
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
    test         = ["CMD-SHELL", "curl -fsS http://localhost:$${PORT}${var.app.healthcheck_path} || exit 1"]
    timeout      = "3s"
  }

  restart      = "unless-stopped"
  stdin_open   = var.app.mode == "dev"
  tty          = var.app.mode == "dev"
  wait         = true
  wait_timeout = var.app.mode == "dev" ? 180 : 90
}
