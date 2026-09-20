resource "docker_image" "rabbitmq" {
  name = "rabbitmq:4.1-management"
}

resource "docker_container" "rabbitmq" {
  entrypoint = ["/bin/sh", "-c", "export RABBITMQ_DEFAULT_PASS=\"$(cat /run/secrets/rabbitmq-password)\"; exec docker-entrypoint.sh rabbitmq-server"]
  image      = docker_image.rabbitmq.image_id
  name       = "${var.name_prefix}-rabbitmq"

  env = [
    "RABBITMQ_DEFAULT_USER=${var.username}",
    "RABBITMQ_DEFAULT_VHOST=${var.virtual_host}"
  ]

  upload {
    content = <<-EOT
      max_message_size = ${var.max_message_bytes}
      listeners.tcp.default = ${var.port}
      default_user_tags.administrator = false
    EOT
    file    = "/etc/rabbitmq/rabbitmq.conf"
  }

  dynamic "networks_advanced" {
    for_each = concat([var.observability_network], values(var.site_networks))

    content {
      aliases = ["rabbitmq"]
      name    = networks_advanced.value
    }
  }

  volumes {
    container_path = "/etc/rabbitmq/enabled_plugins"
    host_path      = abspath("${path.module}/config/enabled_plugins")
    read_only      = true
  }

  volumes {
    container_path = "/run/secrets/rabbitmq-password"
    host_path      = var.password_file
    read_only      = true
  }

  healthcheck {
    interval     = "10s"
    retries      = 10
    start_period = "20s"
    test         = ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
    timeout      = "5s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}
