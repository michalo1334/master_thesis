output "container_names" {
  description = "Evaluation-compute container name per site."
  value       = { for site, container in docker_container.evaluation_compute : site => container.name }
}

output "internal_service_urls" {
  description = "Site-local service URL per site."
  value       = { for site in keys(var.sites) : site => "http://${local.service_alias}:${var.container_port}" }
}

output "loopback_service_urls" {
  description = "Host loopback service URL per site."
  value       = { for site, port in var.host_ports : site => "http://127.0.0.1:${port}" }
}

output "image_id" {
  description = "Built evaluation-compute image ID."
  value       = docker_image.evaluation_compute.image_id
}
