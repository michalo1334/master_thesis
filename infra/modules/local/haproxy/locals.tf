locals {
  api_nodes = [
    for key, node in var.nodes : node
    if node.index == 0
  ]

  config = templatefile("${path.module}/config/haproxy.cfg.tftpl", {
    name_prefix = var.name_prefix
    api_nodes   = local.api_nodes
  })
}