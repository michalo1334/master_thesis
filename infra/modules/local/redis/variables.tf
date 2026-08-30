variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "network_name" {
  description = "Docker network name."
  type        = string
}

variable "password_file" {
  description = "Absolute host path to the Redis password file."
  type        = string
}
