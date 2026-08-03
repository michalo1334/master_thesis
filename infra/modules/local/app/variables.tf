variable "name_prefix" {
  type = string
}

variable "app_source_path" {
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

variable "app" {
  type = object({
    mode             = string
    image            = string
    environment      = list(string)
    port             = number
    healthcheck_path = string
    secret_files     = list(string)
  })
}
