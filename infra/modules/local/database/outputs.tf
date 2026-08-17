output "postgres_host" {
  description = "PostgreSQL container hostname."
  value       = local.postgres_host
}

output "postgres_image" {
  description = "PostgreSQL image ID."
  value       = docker_image.postgres.image_id
}

output "postgres_port" {
  description = "PostgreSQL internal port."
  value       = local.postgres_ports[0].internal
}
