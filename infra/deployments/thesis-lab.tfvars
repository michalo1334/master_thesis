deployment = {
  name = "network-defense-local"
  network = {
    sites = {
      site-west = {
        provider = "placeholder-provider"
        region   = "placeholder-region"
        instance = "placeholder-instance"
      }
      site-east = {
        provider = "placeholder-provider"
        region   = "placeholder-region"
        instance = "placeholder-instance"
      }
    }
  }
  application = {
    service_name = "network-defense"
    primary_site = "site-west"
    replicas = {
      site-west = 2
      site-east = 2
    }
  }
  pubsub = {
    adapter = "redis"
  }
  database = {
    name = "network_defense_dev"
    user = "postgres"
  }
}
