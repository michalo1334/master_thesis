resource "docker_image" "dev" {
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
        "lib/network_defense/runtime_config.ex",
        "lib/network_defense_web/telemetry.ex"
      ] : filesha1("${var.app_source_path}/${filename}")
    ]))
  }
}

resource "docker_volume" "build" {
  name = "${var.name_prefix}-app-build"
}

resource "docker_volume" "dependencies" {
  name = "${var.name_prefix}-app-dependencies"
}

resource "docker_container" "setup" {
  attach   = true
  command  = ["sh", "-c", "mix deps.get && mix ecto.migrate && mix run priv/repo/seeds.exs"]
  env      = local.setup_environment
  image    = docker_image.dev.image_id
  must_run = false
  name     = "${var.name_prefix}-app-setup"
  wait     = false

  networks_advanced {
    name = var.site_networks[var.application.primary_site]
  }

  dynamic "volumes" {
    for_each = local.setup_mounts
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
      error_message = "The app setup container must exit successfully."
    }
  }
}

resource "docker_container" "node" {
  for_each = local.nodes

  depends_on = [docker_container.setup]

  env      = local.node_environment[each.key]
  hostname = "app-${each.value.site}-${each.value.index}"
  image    = docker_image.dev.image_id
  name     = "${var.name_prefix}-app-${each.value.site}-${each.value.index}"

  networks_advanced {
    aliases = ["app", "app-${each.value.index}", var.service_name]
    name    = var.site_networks[each.value.site]
  }

  dynamic "ports" {
    for_each = each.value.role == "coordinator" ? local.dev_host_ports : []
    iterator = port

    content {
      external = port.value.external
      internal = port.value.internal
      ip       = "127.0.0.1"
    }
  }

  dynamic "volumes" {
    for_each = local.node_mounts[each.key]
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
    test         = ["CMD-SHELL", "curl -fsS http://localhost:4000/readyz || exit 1"]
    timeout      = "3s"
  }

  restart      = "unless-stopped"
  stdin_open   = true
  tty          = true
  wait         = true
  wait_timeout = 180
}
