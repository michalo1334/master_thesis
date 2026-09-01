variable "adapter" {
  description = "Phoenix PubSub adapter selected by the deployment manifest."
  type        = string
}

variable "analysis_max_zip_bytes" {
  description = "Maximum analysis response size accepted by the application."
  type        = number
}

variable "app_source_path" {
  description = "Absolute host path to the application source directory."
  type        = string
}

variable "application" {
  description = "Application deployment slice."
  type = object({
    primary_site = string
  })
}

variable "database" {
  description = "Database deployment slice."
  type = object({
    name = string
    user = string
  })
}

variable "database_host" {
  description = "PostgreSQL hostname available on site networks."
  type        = string
}

variable "database_port" {
  description = "PostgreSQL port available on site networks."
  type        = number
}

variable "host" {
  description = "Phoenix host name."
  type        = string
}

variable "host_ports" {
  description = "Application host port bindings."
  type = object({
    http     = number
    debugger = number
  })
}

variable "log_level" {
  description = "Application file log level."
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

variable "nodes" {
  description = "Application nodes keyed by stable node identifier."
  type = map(object({
    site  = string
    index = number
  }))
}

variable "secret_mount_path" {
  description = "Host path to the directory containing secret files."
  type        = string
}

variable "service_name" {
  description = "Application service name."
  type        = string
}

variable "site_networks" {
  description = "Docker network name per declared site."
  type        = map(string)
}

variable "sites" {
  description = "Declared sites keyed by site name."
  type = map(object({
    provider = string
    region   = string
    instance = string
  }))
}
