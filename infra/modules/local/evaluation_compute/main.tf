locals {
  service_alias = "evaluation-compute"
  source_files = sort(concat(
    [".dockerignore", "Dockerfile", "pyproject.toml", "uv.lock"],
    [
      for filename in fileset(var.source_path, "src/**") : filename
      if !strcontains(filename, "/__pycache__/") &&
      !endswith(filename, ".pyc") &&
      !endswith(filename, ".pyo")
    ]
  ))
}

resource "docker_image" "evaluation_compute" {
  name = var.image_name

  build {
    context    = var.source_path
    dockerfile = "Dockerfile"
  }

  triggers = {
    source_hash = sha1(join("", [
      for filename in local.source_files :
      format("%s:%s", filename, filesha1("${var.source_path}/${filename}"))
    ]))
  }

}

resource "docker_container" "evaluation_compute" {
  for_each = var.sites

  env = [
    "EVALUATION_BIND_HOST=0.0.0.0",
    "EVALUATION_PORT=${var.container_port}",
    "EVALUATION_REQUEST_LIMIT_BYTES=${var.request_limit_bytes}",
    "EVALUATION_WORKERS=${var.process_count}",
    "EVALUATION_LOG_LEVEL=${var.log_level}",
    "EVALUATION_SHUTDOWN_TIMEOUT_SECONDS=10",
    "EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES=${var.pilot_limits.max_outer_subsamples}",
    "EVALUATION_PILOT_MAX_BOOTSTRAP_REPLICATES=${var.pilot_limits.max_bootstrap_replicates}",
    "EVALUATION_PILOT_MAX_COMBINED_BOOTSTRAP_WORK=${var.pilot_limits.max_combined_bootstrap_work}"
  ]
  image = docker_image.evaluation_compute.image_id
  name  = "${var.name_prefix}-evaluation-compute-${each.key}"

  networks_advanced {
    aliases = [local.service_alias]
    name    = var.site_networks[each.key]
  }

  ports {
    external = var.host_ports[each.key]
    internal = var.container_port
    ip       = "127.0.0.1"
  }

  healthcheck {
    interval     = "5s"
    retries      = 12
    start_period = "5s"
    test         = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${var.container_port}/ready', timeout=2)"]
    timeout      = "3s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}
