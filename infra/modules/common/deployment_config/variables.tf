variable "deployment" {
  description = "Deployment configuration: name, network sites, application, pubsub adapter, and database."
  type = object({
    name = string
    network = object({
      sites = map(object({
        provider = string
        region   = string
        instance = string
      }))
    })
    application = object({
      service_name = string
      primary_site = string
      replicas     = map(number)
    })
    pubsub = object({
      adapter = string
    })
    database = object({
      name = string
      user = string
    })
  })

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.deployment.name)) && length(var.deployment.name) <= 63
    error_message = "deployment.name must be a lowercase DNS-label-safe name of at most 63 characters."
  }

  validation {
    condition     = length(var.deployment.network.sites) >= 1
    error_message = "network.sites must contain at least one site."
  }

  validation {
    condition = alltrue([
      for key, site in var.deployment.network.sites :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", key)) && length(key) <= 63 &&
      trimspace(site.provider) != "" && trimspace(site.region) != "" && trimspace(site.instance) != ""
    ])
    error_message = "Each network site must have a lowercase DNS-label-safe key of at most 63 characters and nonempty provider, region, and instance."
  }

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.deployment.application.service_name)) && length(var.deployment.application.service_name) <= 63
    error_message = "application.service_name must be a lowercase DNS-label-safe name of at most 63 characters."
  }

  validation {
    condition     = contains(keys(var.deployment.network.sites), var.deployment.application.primary_site)
    error_message = "application.primary_site must reference an existing site key in network.sites."
  }

  validation {
    condition = alltrue([
      for key, replicas in var.deployment.application.replicas :
      contains(keys(var.deployment.network.sites), key) &&
      replicas >= 2 && replicas <= 5
    ])
    error_message = "Each replica key must match a network site and each replica count must be between 2 and 5."
  }

  validation {
    condition     = sum([for replicas in values(var.deployment.application.replicas) : replicas]) >= 2
    error_message = "Total application replicas across sites must be at least 2."
  }

  validation {
    condition     = sort(keys(var.deployment.application.replicas)) == sort(keys(var.deployment.network.sites))
    error_message = "application.replicas keys must exactly match network.sites keys."
  }

  validation {
    condition     = contains(["redis", "pg2"], var.deployment.pubsub.adapter)
    error_message = "pubsub.adapter must be redis or pg2."
  }

  validation {
    condition     = trimspace(var.deployment.database.name) != "" && trimspace(var.deployment.database.user) != ""
    error_message = "database.name and database.user must be nonempty."
  }

  validation {
    condition = alltrue([
      for id in [var.deployment.database.name, var.deployment.database.user] :
      can(regex("^[A-Za-z_][A-Za-z0-9_]*$", id)) && length(id) <= 63
    ])
    error_message = "database.name and database.user must be PostgreSQL identifiers of at most 63 characters."
  }
}
