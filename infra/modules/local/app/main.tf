terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

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

locals {
  image_id = var.app.mode == "dev" ? docker_image.dev[0].image_id : docker_image.prod[0].image_id
  ports = var.app.mode == "dev" ? [
    { internal = var.app.port, external = var.app.port, ip = "127.0.0.1" },
    { internal = 4001, external = 4001, ip = "127.0.0.1" },
    { internal = 5173, external = 5173, ip = "127.0.0.1" },
    { internal = 9229, external = 9229, ip = "127.0.0.1" }
    ] : [
    { internal = var.app.port, external = var.app.port, ip = "127.0.0.1" }
  ]
  volumes = concat(
    var.app.mode == "dev" ? [
      { host_path = "${var.app_source_path}/lib", container_path = "/app/lib" },
      { host_path = "${var.app_source_path}/priv", container_path = "/app/priv" },
      { host_path = "${var.app_source_path}/test", container_path = "/app/test" },
      { host_path = "${var.app_source_path}/config", container_path = "/app/config" },
      { host_path = "${var.app_source_path}/assets/js", container_path = "/app/assets/js" },
      { host_path = "${var.app_source_path}/assets/css", container_path = "/app/assets/css" },
      { host_path = "${var.app_source_path}/assets/svelte", container_path = "/app/assets/svelte" },
      { host_path = "${var.app_source_path}/assets/vite.config.mjs", container_path = "/app/assets/vite.config.mjs" },
      { volume_name = docker_volume.build[0].name, container_path = "/app/_build_docker" },
      { volume_name = docker_volume.dependencies[0].name, container_path = "/app/deps" }
    ] : [],
    [
      { volume_name = var.log_volume_name, container_path = "/var/log/network_defense" },
      { host_path = var.secret_mount_path, container_path = "/run/secrets", read_only = true }
    ]
  )
}

resource "docker_container" "migrate" {
  count = var.app.mode == "prod" ? 1 : 0

  name     = "${var.name_prefix}-app-migrate"
  image    = local.image_id
  command  = ["/app/bin/migrate"]
  attach   = true
  must_run = false
  env      = var.app.environment

  networks_advanced {
    name = var.network_name
  }

  dynamic "volumes" {
    for_each = [{ host_path = var.secret_mount_path, container_path = "/run/secrets", read_only = true }]
    iterator = mount

    content {
      host_path      = mount.value.host_path
      container_path = mount.value.container_path
      read_only      = mount.value.read_only
    }
  }
}

resource "docker_container" "setup" {
  count = var.app.mode == "dev" ? 1 : 0

  name     = "${var.name_prefix}-app-setup"
  image    = local.image_id
  command  = ["sh", "-c", "mix deps.get && mix ecto.migrate && mix run priv/repo/seeds.exs"]
  attach   = true
  must_run = false
  env      = var.app.environment

  networks_advanced {
    name = var.network_name
  }

  dynamic "volumes" {
    for_each = local.volumes
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }
}

resource "docker_container" "app" {
  name  = "${var.name_prefix}-app"
  image = local.image_id
  env   = var.app.environment

  networks_advanced {
    name    = var.network_name
    aliases = ["network_defense"]
  }

  dynamic "ports" {
    for_each = local.ports
    iterator = port

    content {
      internal = port.value.internal
      external = port.value.external
      ip       = port.value.ip
    }
  }

  dynamic "volumes" {
    for_each = local.volumes
    iterator = mount

    content {
      container_path = mount.value.container_path
      host_path      = try(mount.value.host_path, null)
      volume_name    = try(mount.value.volume_name, null)
      read_only      = try(mount.value.read_only, false)
    }
  }

  healthcheck {
    test         = ["CMD-SHELL", "curl -fsS http://localhost:$${PORT}${var.app.healthcheck_path} || exit 1"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 6
    start_period = "20s"
  }

  depends_on   = [docker_container.migrate, docker_container.setup]
  restart      = "unless-stopped"
  stdin_open   = var.app.mode == "dev"
  tty          = var.app.mode == "dev"
  wait         = true
  wait_timeout = var.app.mode == "dev" ? 180 : 90
}

output "container_id" {
  value = docker_container.app.id
}
