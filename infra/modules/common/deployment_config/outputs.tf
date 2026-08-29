output "config" {
  description = "Full deployment configuration object."
  value       = var.deployment
}

output "sites" {
  description = "Network sites keyed by site name."
  value       = local.sites
}

output "nodes" {
  description = "Application nodes keyed as node-<site>-<index>, each with site and index."
  value       = local.nodes
}

output "application" {
  description = "Application configuration."
  value       = var.deployment.application
}

output "pubsub" {
  description = "Pubsub adapter configuration."
  value       = var.deployment.pubsub
}

output "database" {
  description = "Database configuration."
  value       = var.deployment.database
}
