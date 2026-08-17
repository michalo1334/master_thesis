variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "network_name" {
  description = "Docker network name."
  type        = string
}

variable "pgadmin_email" {
  description = "pgAdmin default admin email."
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
