resource "docker_image" "redis" {
  name = "redis:8.2"
}

resource "docker_image" "redis_exporter" {
  name = "quay.io/oliver006/redis_exporter:v1.70.0-alpine"
}

resource "docker_container" "redis" {
  command = ["sh", "-c", local.entrypoint_script]
  image   = docker_image.redis.image_id
  name    = "${var.name_prefix}-redis"

  dynamic "networks_advanced" {
    for_each = values(var.site_networks)

    content {
      aliases = ["redis"]
      name    = networks_advanced.value
    }
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

resource "docker_container" "redis_exporter" {
  image = docker_image.redis_exporter.image_id
  name  = "${var.name_prefix}-redis-exporter"
  user  = "0"

  entrypoint = ["/bin/sh", "-c", <<-EOT
    set -eu
    password="$(tr -d '\r\n' < /run/secrets/redis-password)"
    printf '{"redis://redis:6379":"%s"}\n' "$password" > /tmp/redis-passwords.json
    unset password
    exec /redis_exporter --redis.addr=redis://redis:6379 --redis.password-file=/tmp/redis-passwords.json
  EOT
  ]

  networks_advanced {
    aliases = ["redis-exporter"]
    name    = var.observability_network
  }

  networks_advanced {
    name = values(var.site_networks)[0]
  }

  volumes {
    container_path = "/run/secrets/redis-password"
    host_path      = var.password_file
    read_only      = true
  }

  tmpfs = {
    "/tmp" = "rw,noexec,nosuid,nodev,size=1m,mode=0700"
  }

  healthcheck {
    interval     = "10s"
    retries      = 6
    start_period = "20s"
    test         = ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:9121/metrics || exit 1"]
    timeout      = "3s"
  }

  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 90
}
