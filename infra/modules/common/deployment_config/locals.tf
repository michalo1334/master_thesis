locals {
  sites = {
    for key, site in var.deployment.network.sites :
    key => {
      provider = site.provider
      region   = site.region
      instance = site.instance
    }
  }

  nodes = merge([
    for key, replicas in var.deployment.application.replicas :
    {
      for index in range(replicas) :
      "node-${key}-${index}" => {
        site  = key
        index = index
      }
    }
  ]...)
}
