resource "docker_image" "haproxy" {
  name = "haproxy:2.9-alpine"
}

resource "docker_container" "haproxy" {
  image = docker_image.haproxy.image_id
  name  = "${var.name_prefix}-haproxy"

  ports {
    internal = 80
    external = var.host_port
    ip       = "127.0.0.1"
  }

  dynamic "networks_advanced" {
    for_each = values(var.site_networks)

    content {
      name = networks_advanced.value
    }
  }

  upload {
    content = local.config
    file    = "/usr/local/etc/haproxy/haproxy.cfg"
  }

  restart = "unless-stopped"
}
