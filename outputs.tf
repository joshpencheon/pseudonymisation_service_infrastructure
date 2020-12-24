output "release_tag" {
  value = local.release_tag
}

output "service_node_port" {
  value = module.pseudo_service.webapp_service.spec[0].port[0].node_port
}
