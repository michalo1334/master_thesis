variable "analysis_port" {
  description = "Loopback host port for the analysis service."
  type        = number
  default     = 8080

  validation {
    condition     = var.analysis_port >= 1 && var.analysis_port <= 65535
    error_message = "analysis_port must be between 1 and 65535."
  }
}

variable "analysis_source_path" {
  description = "Absolute host path to the analysis source directory."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "network_name" {
  description = "Docker network name."
  type        = string
}
