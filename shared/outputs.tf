output "shared_namespace" {
  value = kubernetes_namespace.pseudonymisation_service
}

output "shared_postgres_service" {
  value = kubernetes_service.shared_postgres
}
