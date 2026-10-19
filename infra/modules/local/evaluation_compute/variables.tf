variable "name_prefix" {
  description = "Prefix for evaluation-compute resources."
  type        = string

  validation {
    condition     = trimspace(var.name_prefix) != ""
    error_message = "name_prefix must not be empty."
  }
}

variable "source_path" {
  description = "Absolute path to the evaluation-compute build context."
  type        = string

  validation {
    condition     = trimspace(var.source_path) != ""
    error_message = "source_path must not be empty."
  }
}

variable "sites" {
  description = "Declared deployment sites."
  type        = map(any)

  validation {
    condition     = length(var.sites) > 0
    error_message = "sites must not be empty."
  }
}

variable "site_networks" {
  description = "Docker network name per declared site."
  type        = map(string)

  validation {
    condition     = alltrue([for network in values(var.site_networks) : trimspace(network) != ""])
    error_message = "Every site network name must not be empty."
  }
}

variable "image_name" {
  description = "Local image name and tag."
  type        = string

  validation {
    condition     = trimspace(var.image_name) != ""
    error_message = "image_name must not be empty."
  }
}

variable "container_port" {
  description = "Service port inside each container."
  type        = number

  validation {
    condition = (
      var.container_port == floor(var.container_port) &&
      var.container_port >= 1 && var.container_port <= 65535
    )
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "host_ports" {
  description = "Loopback host port per site."
  type        = map(number)

  validation {
    condition = (
      alltrue([
        for port in values(var.host_ports) :
        port == floor(port) && port >= 1 && port <= 65535
      ]) &&
      length(values(var.host_ports)) == length(distinct(values(var.host_ports)))
    )
    error_message = "Host ports must be distinct integers between 1 and 65535."
  }

  validation {
    condition = (
      toset(keys(var.host_ports)) == toset(keys(var.sites)) &&
      toset(keys(var.host_ports)) == toset(keys(var.site_networks))
    )
    error_message = "sites, site_networks, and host_ports must have exactly the same keys."
  }
}

variable "request_limit_bytes" {
  description = "Maximum JSON request size in bytes."
  type        = number

  validation {
    condition = (
      var.request_limit_bytes == floor(var.request_limit_bytes) &&
      var.request_limit_bytes > 0
    )
    error_message = "request_limit_bytes must be a positive integer."
  }
}

variable "process_count" {
  description = "Uvicorn worker count per site."
  type        = number

  validation {
    condition     = var.process_count == floor(var.process_count) && var.process_count > 0
    error_message = "process_count must be a positive integer."
  }
}

variable "log_level" {
  description = "Uvicorn log level."
  type        = string

  validation {
    condition     = contains(["debug", "info", "warning", "error", "critical"], lower(var.log_level))
    error_message = "log_level must be debug, info, warning, error, or critical."
  }
}

variable "pilot_limits" {
  description = "Stage 4 Pilot compute resource caps. Deployment caps, not scientific settings."
  type = object({
    max_outer_subsamples        = number
    max_bootstrap_replicates    = number
    max_combined_bootstrap_work = number
  })

  validation {
    condition = (
      var.pilot_limits.max_outer_subsamples == floor(var.pilot_limits.max_outer_subsamples) &&
      var.pilot_limits.max_outer_subsamples > 0 &&
      var.pilot_limits.max_bootstrap_replicates == floor(var.pilot_limits.max_bootstrap_replicates) &&
      var.pilot_limits.max_bootstrap_replicates > 0 &&
      var.pilot_limits.max_combined_bootstrap_work == floor(var.pilot_limits.max_combined_bootstrap_work) &&
      var.pilot_limits.max_combined_bootstrap_work > 0
    )
    error_message = "Pilot compute caps must be positive integers."
  }
}
