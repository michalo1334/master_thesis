variable "adapter" {
  description = "Phoenix PubSub adapter selected by the deployment manifest."
  type        = string
}

variable "app_source_path" {
  description = "Absolute host path to the application source directory."
  type        = string
}

variable "application" {
  description = "Application deployment slice."
  type = object({
    primary_site = string
  })
}

variable "database" {
  description = "Database deployment slice."
  type = object({
    name = string
    user = string
  })
}

variable "database_host" {
  description = "PostgreSQL hostname available on site networks."
  type        = string
}

variable "database_port" {
  description = "PostgreSQL port available on site networks."
  type        = number

  validation {
    condition = (
      var.database_port == floor(var.database_port) &&
      var.database_port >= 1 && var.database_port <= 65535
    )
    error_message = "database_port must be an integer between 1 and 65535."
  }
}

variable "evaluation_compute_urls" {
  description = "Site-local evaluation-compute URL per site."
  type        = map(string)
}

variable "host" {
  description = "Phoenix host name."
  type        = string

  validation {
    condition     = trimspace(var.host) != ""
    error_message = "host must not be empty."
  }
}

variable "host_ports" {
  description = "Application host port bindings."
  type = object({
    http     = number
    debugger = number
  })

  validation {
    condition = (
      alltrue([
        for port in values(var.host_ports) :
        port == floor(port) && port >= 1 && port <= 65535
      ]) &&
      length(values(var.host_ports)) == length(distinct(values(var.host_ports)))
    )
    error_message = "Application host ports must be distinct integers between 1 and 65535."
  }
}

variable "log_level" {
  description = "Application file log level."
  type        = string

  validation {
    condition     = contains(["debug", "info", "warning", "error"], lower(var.log_level))
    error_message = "log_level must be debug, info, warning, or error."
  }
}

variable "log_volume_name" {
  description = "Name of the shared log volume."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "nodes" {
  description = "Application nodes keyed by stable node identifier."
  type = map(object({
    site  = string
    index = number
  }))

  validation {
    condition = (
      length(var.nodes) > 0 &&
      alltrue([for node in values(var.nodes) : node.index == floor(node.index) && node.index >= 0])
    )
    error_message = "nodes must not be empty, and every node index must be a non-negative integer."
  }
}

variable "rabbitmq" {
  description = "RabbitMQ connection settings."
  type = object({
    host                         = string
    max_message_bytes            = number
    port                         = number
    result_inactivity_timeout_ms = number
    username                     = string
    virtual_host                 = string
  })

  validation {
    condition = (
      trimspace(var.rabbitmq.host) != "" &&
      trimspace(var.rabbitmq.username) != "" &&
      var.rabbitmq.port == floor(var.rabbitmq.port) &&
      var.rabbitmq.port >= 1 && var.rabbitmq.port <= 65535 &&
      var.rabbitmq.max_message_bytes == floor(var.rabbitmq.max_message_bytes) &&
      var.rabbitmq.max_message_bytes > 0 &&
      var.rabbitmq.result_inactivity_timeout_ms == floor(var.rabbitmq.result_inactivity_timeout_ms) &&
      var.rabbitmq.result_inactivity_timeout_ms > 0
    )
    error_message = "RabbitMQ settings require names, an integer port, and positive integer byte and timeout limits."
  }
}

variable "secret_mount_path" {
  description = "Host path to the directory containing secret files."
  type        = string
}

variable "service_name" {
  description = "Application service name."
  type        = string
}

variable "site_networks" {
  description = "Docker network name per declared site."
  type        = map(string)
}

variable "sites" {
  description = "Declared sites keyed by site name."
  type = map(object({
    provider = string
    region   = string
    instance = string
  }))

  validation {
    condition = (
      length(var.sites) > 0 &&
      toset(keys(var.sites)) == toset(keys(var.site_networks)) &&
      toset(keys(var.sites)) == toset(keys(var.evaluation_compute_urls)) &&
      contains(keys(var.sites), var.application.primary_site) &&
      alltrue([for node in values(var.nodes) : contains(keys(var.sites), node.site)])
    )
    error_message = "Site networks, compute URLs, the primary site, and every application node must match declared site keys."
  }
}

variable "pilot_limits" {
  description = "Stage 4 Pilot resource caps for the application and setup containers."
  type = object({
    snapshot_payload_bytes  = number
    snapshot_comparisons    = number
    comparison_count        = number
    candidate_count         = number
    plans_per_side          = number
    attack_columns          = number
    work_items              = number
    outer_subsamples        = number
    bootstrap_replicates    = number
    candidate_request_bytes = number
  })

  validation {
    condition = alltrue([
      for value in values(var.pilot_limits) : value == floor(value) && value > 0
    ])
    error_message = "Every Pilot limit must be a positive integer."
  }
}
