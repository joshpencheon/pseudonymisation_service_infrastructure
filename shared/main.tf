resource "kubernetes_namespace" "pseudonymisation_service" {
  metadata {
    name = "pseudonymisation-service"
    labels = {
      app  = "pseudonymisation-service"
      role = "shared"
    }
  }
}

resource "kubernetes_persistent_volume_claim" "postgres" {
  metadata {
    name = "postgres-data-volume-claim"
    namespace = kubernetes_namespace.pseudonymisation_service.id
    labels = {
      app = "pseudonymisation-service"
    }
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    # Using Rancher's local-path-provisioner (on k3s):
    storage_class_name = "local-path"

    resources {
      requests = {
        storage = "500M"
      }
    }
  }

  wait_until_bound = false
}

resource "kubernetes_deployment" "shared_postgres" {
  metadata {
    name = "shared-postgres"
    namespace = kubernetes_namespace.pseudonymisation_service.id
    labels = {
      app = "pseudonymisation-service"
      tier = "db"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "pseudonymisation-service"
        tier = "db"
      }
    }
    template {
      metadata {
        labels = {
          app = "pseudonymisation-service"
          tier = "db"
        }
      }
      spec {
        container {
          image = "postgres:alpine"
          name  = "db"

          port {
            container_port = 5432
          }

          env {
            name = "POSTGRES_PASSWORD"
            value = "password"
          }

          resources {
            limits {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests {
              cpu    = "250m"
              memory = "50Mi"
            }
          }

          volume_mount {
            name = "pg-data-vol"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "pg-data-vol"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "pseudonymisation_service_postgres_policy" {
  metadata {
    name = "pseudonymisation-service-postgres-policy"
    namespace = kubernetes_namespace.pseudonymisation_service.id
  }

  spec {
    pod_selector {
      match_labels = {
        app  = kubernetes_deployment.shared_postgres.metadata[0].labels.app
        tier = kubernetes_deployment.shared_postgres.metadata[0].labels.tier
      }
    }

    # Allow only incoming PG connections, and only from applicable namespaces.
    ingress {
      from {
        namespace_selector {
          match_labels = {
            app = "pseudonymisation-service"
          }
        }
      }

      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # No Egress allowlist at all => no connections out.
    # egress {}

    policy_types = ["Egress"]
  }
}

resource "kubernetes_service" "shared_postgres" {
  metadata {
    name = "db"
    namespace = kubernetes_namespace.pseudonymisation_service.id
    labels = {
      app = "pseudonymisation-service"
    }
  }

  spec {
    selector = {
      app  = kubernetes_deployment.shared_postgres.metadata[0].labels.app
      tier = kubernetes_deployment.shared_postgres.metadata[0].labels.tier
    }

    port {
      port = 5432
    }

    cluster_ip = "None"
  }
}

