output "container_id" {
  description = "ID of the application container."
  value       = docker_container.app.id
}
