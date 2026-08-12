variable "secret_mount_path" {
  type = string
}

variable "app_mode" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.app_mode)
    error_message = "app_mode must be dev or prod."
  }
}

variable "app_image" {
  type     = string
  default  = null
  nullable = true
}

variable "phx_host" {
  type = string
}

variable "app_port" {
  type = number
}

variable "otel_endpoint" {
  type = string
}

variable "log_file_path" {
  type = string
}

variable "log_file_level" {
  type = string
}

variable "postgres_user" {
  type = string
}

variable "postgres_database" {
  type = string
}

variable "grafana_user" {
  type = string
}

variable "pgadmin_email" {
  type = string
}
