variable "app_image" {
  description = "Container image for the app in prod mode. Required when app_mode is prod."
  type        = string
  default     = null
  nullable    = true
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

variable "app_mode" {
  description = "Application run mode."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.app_mode)
    error_message = "app_mode must be dev or prod."
  }
}

variable "app_port" {
  description = "Application HTTP port."
  type        = number
}

variable "grafana_user" {
  description = "Grafana admin username."
  type        = string
}

variable "log_file_level" {
  description = "Log level for the file logger."
  type        = string
}

variable "log_file_path" {
  description = "Absolute path to the JSONL log file inside the app container."
  type        = string
}

variable "otel_endpoint" {
  description = "OTLP HTTP endpoint for traces and metrics."
  type        = string
}

variable "pgadmin_email" {
  description = "pgAdmin default admin email."
  type        = string
}

variable "phx_host" {
  description = "Phoenix host for URL generation."
  type        = string
}

variable "postgres_database" {
  description = "PostgreSQL database name."
  type        = string
}

variable "postgres_user" {
  description = "PostgreSQL username."
  type        = string
}

variable "secret_mount_path" {
  description = "Host path to the directory containing secret files."
  type        = string
}
