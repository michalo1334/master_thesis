output "container_ids" {
  description = "Application container IDs keyed by stable node identifier."
  value = {
    for key in keys(local.nodes) : key => docker_container.node[key].id
  }
}

output "site_primary_node_names" {
  description = "Long node name for replica 0 of each site."
  value = {
    for site in keys(var.sites) :
    site => "app@${one([for network in docker_container.node["node-${site}-0"].network_data : network.ip_address if network.network_name == var.site_networks[site]])}"
  }
}
