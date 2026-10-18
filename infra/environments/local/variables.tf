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
    condition = (
      trimspace(var.application.host) != "" &&
      contains(["debug", "info", "warning", "error"], lower(var.application.log_level)) &&
      alltrue([
        for port in values(var.application.host_ports) :
        port == floor(port) && port >= 1 && port <= 65535
      ]) &&
      length(values(var.application.host_ports)) ==
      length(distinct(values(var.application.host_ports)))
    )
    error_message = "Application settings require a host, a supported log level, and distinct integer ports from 1 through 65535."
  }

  validation {
    condition = length(concat(
      values(var.application.host_ports),
      [
        var.database.host_port,
        var.grafana.host_port,
        var.pgadmin.host_port,
        var.prometheus.host_port
      ],
      values(var.evaluation_compute.host_ports)
      )) == length(distinct(concat(
        values(var.application.host_ports),
        [
          var.database.host_port,
          var.grafana.host_port,
          var.pgadmin.host_port,
          var.prometheus.host_port
        ],
        values(var.evaluation_compute.host_ports)
    )))
    error_message = "All configured host entry ports must be pairwise unique."
  }
}

variable "database" {
  description = "Local PostgreSQL host configuration."
  type = object({
    host_port = number
  })

  validation {
    condition = (
      var.database.host_port == floor(var.database.host_port) &&
      var.database.host_port >= 1 && var.database.host_port <= 65535
    )
    error_message = "database.host_port must be an integer between 1 and 65535."
  }
}

variable "evaluation_compute" {
  description = "Local evaluation-compute configuration."
  type = object({
    container_port      = number
    host_ports          = map(number)
    image_name          = string
    log_level           = string
    process_count       = number
    request_limit_bytes = number
  })

  validation {
    condition = (
      var.evaluation_compute.container_port == floor(var.evaluation_compute.container_port) &&
      var.evaluation_compute.container_port >= 1 &&
      var.evaluation_compute.container_port <= 65535 &&
      alltrue([
        for port in values(var.evaluation_compute.host_ports) :
        port == floor(port) && port >= 1 && port <= 65535
      ]) &&
      length(values(var.evaluation_compute.host_ports)) ==
      length(distinct(values(var.evaluation_compute.host_ports))) &&
      trimspace(var.evaluation_compute.image_name) != "" &&
      contains(["debug", "info", "warning", "error", "critical"], lower(var.evaluation_compute.log_level)) &&
      var.evaluation_compute.process_count == floor(var.evaluation_compute.process_count) &&
      var.evaluation_compute.process_count > 0 &&
      var.evaluation_compute.request_limit_bytes == floor(var.evaluation_compute.request_limit_bytes) &&
      var.evaluation_compute.request_limit_bytes > 0
    )
    error_message = "Evaluation-compute settings require a named image, a supported log level, distinct integer ports, and positive integer process and request limits."
  }
}

variable "grafana" {
  description = "Local Grafana host configuration."
  type = object({
    host_port  = number
    admin_user = string
  })

  validation {
    condition = (
      var.grafana.host_port == floor(var.grafana.host_port) &&
      var.grafana.host_port >= 1 && var.grafana.host_port <= 65535 &&
      trimspace(var.grafana.admin_user) != ""
    )
    error_message = "Grafana requires a non-empty admin user and an integer host port from 1 through 65535."
  }
}

variable "pgadmin" {
  description = "Local pgAdmin host configuration."
  type = object({
    host_port   = number
    admin_email = string
  })

  validation {
    condition = (
      var.pgadmin.host_port == floor(var.pgadmin.host_port) &&
      var.pgadmin.host_port >= 1 && var.pgadmin.host_port <= 65535 &&
      trimspace(var.pgadmin.admin_email) != ""
    )
    error_message = "pgAdmin requires a non-empty admin email and an integer host port from 1 through 65535."
  }
}

variable "prometheus" {
  description = "Local Prometheus host configuration."
  type = object({
    host_port = number
  })

  validation {
    condition = (
      var.prometheus.host_port == floor(var.prometheus.host_port) &&
      var.prometheus.host_port >= 1 && var.prometheus.host_port <= 65535
    )
    error_message = "prometheus.host_port must be an integer between 1 and 65535."
  }
}

variable "secrets" {
  description = "Local secret directory configuration."
  type = object({
    directory = string
  })

  validation {
    condition     = trimspace(var.secrets.directory) != ""
    error_message = "secrets.directory must not be empty."
  }
}
