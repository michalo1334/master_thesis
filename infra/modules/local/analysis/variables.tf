variable "analysis_source_path" {
  description = "Absolute host path to the analysis source directory."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
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
