locals {
  pgadmin_ports = [{ external = var.pgadmin_host_port, internal = 80, ip = "127.0.0.1" }]
  pgadmin_volumes = [
    { container_path = "/var/lib/pgadmin", volume_name = docker_volume.pgadmin_data.name },
    { container_path = "/run/secrets/pgadmin-password", host_path = "${var.secret_mount_path}/pgadmin-password", read_only = true },
    { container_path = "/run/secrets/postgres-password", host_path = "${var.secret_mount_path}/postgres-password", read_only = true }
  ]
  postgres_host  = "postgres"
  postgres_ports = [{ external = var.postgres_host_port, internal = 5432, ip = "127.0.0.1" }]
  postgres_volumes = [
    { container_path = "/var/lib/postgresql", volume_name = docker_volume.postgres_data.name },
    { container_path = "/run/secrets/postgres-password", host_path = "${var.secret_mount_path}/postgres-password", read_only = true }
  ]
}
