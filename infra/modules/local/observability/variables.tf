variable "grafana_user" {
  description = "Grafana admin username."
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

variable "postgres_database" {
  description = "PostgreSQL database name."
  type        = string
}

variable "postgres_host" {
  description = "PostgreSQL hostname."
  type        = string
}

variable "postgres_image" {
  description = "PostgreSQL image ID for the exporter init container."
  type        = string
}

variable "postgres_port" {
  description = "PostgreSQL port."
  type        = number
}

variable "postgres_user" {
  description = "PostgreSQL username."
  type        = string
}

variable "secret_mount_path" {
  description = "Host path to the directory containing secret files."
  type        = string
}
