variable "name_prefix" {
  type = string
}

variable "config_path" {
  type = string
}

variable "network_name" {
  type = string
}

variable "secret_mount_path" {
  type = string
}

variable "log_volume_name" {
  type = string
}

variable "postgres_user" {
  type = string
}

variable "postgres_database" {
  type = string
}

variable "postgres_host" {
  type = string
}

variable "postgres_port" {
  type = number
}

variable "postgres_image" {
  type = string
}

variable "grafana_user" {
  type = string
}
