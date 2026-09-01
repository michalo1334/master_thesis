variable "host_port" {
  description = "Host port on which HAProxy publishes the application HTTP entry point."
  type        = number
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "nodes" {
  description = "Application nodes keyed by stable node identifier."
  type = map(object({
    site  = string
    index = number
  }))
}

variable "site_networks" {
  description = "Docker network name per declared site."
  type        = map(string)
}