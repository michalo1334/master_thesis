locals {
  image_id = var.app.mode == "dev" ? docker_image.dev[0].image_id : docker_image.prod[0].image_id
  ports = var.app.mode == "dev" ? [
    { external = var.app.port, internal = var.app.port, ip = "127.0.0.1" },
    { external = 4001, internal = 4001, ip = "127.0.0.1" },
    { external = 5173, internal = 5173, ip = "127.0.0.1" },
    { external = 9229, internal = 9229, ip = "127.0.0.1" }
    ] : [
    { external = var.app.port, internal = var.app.port, ip = "127.0.0.1" }
  ]
  volumes = concat(
    var.app.mode == "dev" ? [
      { container_path = "/app/lib", host_path = "${var.app_source_path}/lib" },
      { container_path = "/app/priv", host_path = "${var.app_source_path}/priv" },
      { container_path = "/app/test", host_path = "${var.app_source_path}/test" },
      { container_path = "/app/config", host_path = "${var.app_source_path}/config" },
      { container_path = "/app/assets/js", host_path = "${var.app_source_path}/assets/js" },
      { container_path = "/app/assets/css", host_path = "${var.app_source_path}/assets/css" },
      { container_path = "/app/assets/svelte", host_path = "${var.app_source_path}/assets/svelte" },
      { container_path = "/app/assets/vite.config.mjs", host_path = "${var.app_source_path}/assets/vite.config.mjs" },
      { container_path = "/app/_build_docker", volume_name = docker_volume.build[0].name },
      { container_path = "/app/deps", volume_name = docker_volume.dependencies[0].name }
    ] : [],
    [
      { container_path = "/var/log/network_defense", volume_name = var.log_volume_name },
      { container_path = "/run/secrets", host_path = var.secret_mount_path, read_only = true }
    ]
  )
}
