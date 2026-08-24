resource "docker_image" "analysis" {
  name = local.image_name

  build {
    context    = var.analysis_source_path
    dockerfile = "Dockerfile"
  }

  triggers = {
    build_inputs = sha1(join("", [
      for filename in local.source_files : filesha1("${var.analysis_source_path}/${filename}")
    ]))
  }
}

resource "docker_container" "analysis" {
  image = docker_image.analysis.image_id
  name  = "${var.name_prefix}-analysis"

  networks_advanced {
    aliases = ["analysis"]
    name    = var.network_name
  }

  ports {
    external = var.analysis_port
    internal = 8080
    ip       = "127.0.0.1"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}
