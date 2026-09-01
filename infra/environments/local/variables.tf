variable "deployment" {
  description = "Provider-neutral deployment configuration validated by deployment_config."
  type        = any
  nullable    = false
}

variable "application" {
  description = "Local application host configuration."
  type = object({
    host      = string
    log_level = string
    host_ports = object({
      http     = number
      debugger = number
    })
  })

  validation {
    condition     = alltrue([for port in values(var.application.host_ports) : port >= 1 && port <= 65535])
    error_message = "Every application host port must be between 1 and 65535."
  }
}

variable "database" {
  description = "Local PostgreSQL host configuration."
  type = object({
    host_port = number
  })

  validation {
    condition     = var.database.host_port >= 1 && var.database.host_port <= 65535
    error_message = "database.host_port must be between 1 and 65535."
  }
}

variable "grafana" {
  description = "Local Grafana host configuration."
  type = object({
    host_port  = number
    admin_user = string
  })

  validation {
    condition     = var.grafana.host_port >= 1 && var.grafana.host_port <= 65535
    error_message = "grafana.host_port must be between 1 and 65535."
  }
}

variable "pgadmin" {
  description = "Local pgAdmin host configuration."
  type = object({
    host_port   = number
    admin_email = string
  })

  validation {
    condition     = var.pgadmin.host_port >= 1 && var.pgadmin.host_port <= 65535
    error_message = "pgadmin.host_port must be between 1 and 65535."
  }
}

variable "prometheus" {
  description = "Local Prometheus host configuration."
  type = object({
    host_port = number
  })

  validation {
    condition     = var.prometheus.host_port >= 1 && var.prometheus.host_port <= 65535
    error_message = "prometheus.host_port must be between 1 and 65535."
  }
}

variable "secrets" {
  description = "Local secret directory configuration."
  type = object({
    directory = string
  })
}
