resource "docker_image" "redis" {
  name = "redis:8.2"
}

resource "docker_container" "redis" {
  command = ["sh", "-c", local.entrypoint_script]
  image   = docker_image.redis.image_id
  name    = "${var.name_prefix}-redis"

  networks_advanced {
    aliases = ["redis"]
    name    = var.network_name
  }

  volumes {
    container_path = "/run/secrets/redis-password"
    host_path      = var.password_file
    read_only      = true
  }

  tmpfs = {
    "/data" = "rw"
  }

  healthcheck {
    interval     = "10s"
    retries      = 10
    start_period = "10s"
    test         = ["CMD-SHELL", "REDISCLI_AUTH=\"$(cat /run/secrets/redis-password)\" redis-cli ping 2>/dev/null | grep -qx PONG"]
    timeout      = "3s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}
