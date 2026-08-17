output "container_id" {
  description = "ID of the primary application container (deprecated, use container_ids)."
  value       = docker_container.app[0].id
}

output "container_ids" {
  description = "IDs of all application containers."
  value       = [for c in docker_container.app : c.id]
}
