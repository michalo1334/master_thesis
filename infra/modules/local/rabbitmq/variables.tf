variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "max_message_bytes" {
  description = "Maximum RabbitMQ message size in bytes."
  type        = number
}

variable "observability_network" {
  description = "Docker observability network name."
  type        = string
}

variable "port" {
  description = "RabbitMQ AMQP listener port."
  type        = number
}

variable "password_file" {
  description = "Absolute host path to the RabbitMQ password file."
  type        = string
}

variable "site_networks" {
  description = "Docker network name per declared site."
  type        = map(string)
}

variable "username" {
  description = "RabbitMQ application username."
  type        = string
}

variable "virtual_host" {
  description = "RabbitMQ application virtual host."
  type        = string
}
