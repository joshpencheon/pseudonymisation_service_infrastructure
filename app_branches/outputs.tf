output "release_tag" {
  value = local.release_tag
}

output "service_hostname" {
  value = module.pseudo_service.webapp_ingress.spec[0].rule[0].host
}
