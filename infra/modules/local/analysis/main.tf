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
  for_each = var.sites

  image = docker_image.analysis.image_id
  name  = "${var.name_prefix}-analysis-${each.key}"

  env = [
    "NETWORK_DEFENSE_ANALYSIS_MAX_RESPONSE_BYTES=${local.max_response_size}"
  ]

  networks_advanced {
    aliases = ["analysis"]
    name    = var.site_networks[each.key]
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}
