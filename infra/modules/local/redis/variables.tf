variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "site_networks" {
  description = "Docker network name per declared site."
  type        = map(string)
}

variable "password_file" {
  description = "Absolute host path to the Redis password file."
  type        = string
}

variable "observability_network" {
  description = "Docker observability network name."
  type        = string
}
