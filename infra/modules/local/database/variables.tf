variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "observability_name" {
  description = "Docker observability network name."
  type        = string
}

variable "pgadmin_email" {
  description = "pgAdmin default admin email."
  type        = string
}

variable "pgadmin_host_port" {
  description = "Loopback host port for the pgAdmin service."
  type        = number

  validation {
    condition     = var.pgadmin_host_port >= 1 && var.pgadmin_host_port <= 65535
    error_message = "pgadmin_host_port must be between 1 and 65535."
  }
}

variable "postgres_database" {
  description = "PostgreSQL database name."
  type        = string
}

variable "postgres_host_port" {
  description = "Loopback host port for the PostgreSQL service."
  type        = number

  validation {
    condition     = var.postgres_host_port >= 1 && var.postgres_host_port <= 65535
    error_message = "postgres_host_port must be between 1 and 65535."
  }
}

variable "postgres_user" {
  description = "PostgreSQL username."
  type        = string
}

variable "secret_mount_path" {
  description = "Host path to the directory containing secret files."
  type        = string
}

variable "site_networks" {
  description = "Docker network name per declared site."
  type        = map(string)
}
