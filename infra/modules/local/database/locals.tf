locals {
  pgadmin_ports = [{ external = 5050, internal = 80, ip = "127.0.0.1" }]
  pgadmin_volumes = [
    { container_path = "/var/lib/pgadmin", volume_name = docker_volume.pgadmin_data.name },
    { container_path = "/run/secrets", host_path = var.secret_mount_path, read_only = true }
  ]
  postgres_host  = "postgres"
  postgres_ports = [{ external = 5433, internal = 5432, ip = "127.0.0.1" }]
  postgres_volumes = [
    { container_path = "/var/lib/postgresql", volume_name = docker_volume.postgres_data.name },
    { container_path = "/run/secrets", host_path = var.secret_mount_path, read_only = true }
  ]
}
