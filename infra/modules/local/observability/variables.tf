variable "database" {
  description = "Shared PostgreSQL identity."
  type = object({
    name = string
    user = string
  })
}

variable "grafana_admin_user" {
  description = "Grafana administrator username."
  type        = string
}

variable "grafana_host_port" {
  description = "Loopback host port for Grafana."
  type        = number

  validation {
    condition     = var.grafana_host_port >= 1 && var.grafana_host_port <= 65535
    error_message = "grafana_host_port must be between 1 and 65535."
  }
}

variable "log_volume_name" {
  description = "Shared application log volume name."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "observability_network" {
  description = "Docker observability network name."
  type        = string
}

variable "postgres_host" {
  description = "PostgreSQL hostname on the observability network."
  type        = string
}

variable "postgres_image" {
  description = "PostgreSQL image ID for the exporter setup container."
  type        = string
}

variable "postgres_port" {
  description = "PostgreSQL port on the observability network."
  type        = number
}

variable "prometheus_host_port" {
  description = "Loopback host port for Prometheus."
  type        = number

  validation {
    condition     = var.prometheus_host_port >= 1 && var.prometheus_host_port <= 65535
    error_message = "prometheus_host_port must be between 1 and 65535."
  }
}

variable "secret_mount_path" {
  description = "Host path to the directory containing secret files."
  type        = string
}

variable "service_name" {
  description = "Application service name used by telemetry configuration."
  type        = string
}
