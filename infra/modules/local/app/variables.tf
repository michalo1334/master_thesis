variable "app" {
  description = "Application container configuration."
  type = object({
    environment      = list(string)
    healthcheck_path = string
    image            = string
    mode             = string
    port             = number
    secret_files     = list(string)
  })
}

variable "app_replicas" {
  description = "Number of app replicas."
  type        = number
  default     = 2

  validation {
    condition     = var.app_replicas >= 1 && var.app_replicas <= 5
    error_message = "app_replicas must be between 1 and 5."
  }
}

variable "app_source_path" {
  description = "Absolute host path to the application source directory."
  type        = string
}

variable "log_volume_name" {
  description = "Name of the shared log volume."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "network_name" {
  description = "Docker network name."
  type        = string
}

variable "secret_mount_path" {
  description = "Host path to the directory containing secret files."
  type        = string
}
