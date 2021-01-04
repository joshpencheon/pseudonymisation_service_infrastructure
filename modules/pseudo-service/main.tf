resource "kubernetes_namespace" "pseudonymisation_service" {
  metadata {
    name = "pseudonymisation-service-${var.label}"
    labels = {
      app = "pseudonymisation-service"
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

resource "kubernetes_deployment" "postgres" {
  metadata {
    name = "postgres"
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
        app  = kubernetes_deployment.postgres.metadata[0].labels.app
        tier = kubernetes_deployment.postgres.metadata[0].labels.tier
      }
    }

    # Allow PG connections in only from the webapp:
    ingress {
      ports {
        port     = "5432"
        protocol = "TCP"
      }

      from {
        pod_selector {
          match_labels = {
            app  = kubernetes_deployment.webapp.metadata[0].labels.app
            tier = kubernetes_deployment.webapp.metadata[0].labels.tier
          }
        }
      }
    }

    # No Egress allowlist at all => no connections out.
    # egress {}

    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name = "db"
    namespace = kubernetes_namespace.pseudonymisation_service.id
    labels = {
      app = "pseudonymisation-service"
    }
  }

  spec {
    selector = {
      app  = kubernetes_deployment.postgres.metadata[0].labels.app
      tier = kubernetes_deployment.postgres.metadata[0].labels.tier
    }

    port {
      port = 5432
    }

    cluster_ip = "None"
  }
}

resource "kubernetes_config_map" "webapp" {
  metadata {
    name = "webapp-config"
    namespace = kubernetes_namespace.pseudonymisation_service.id
    labels = {
      app = "pseudonymisation-service"
    }
  }

  data = {
    "DATABASE_HOST"       = "db"
    "DATABASE_USERNAME"   = "postgres"
    "DATABASE_PASSWORD"   = "password"
    "RAILS_ENV"           = "production"
    "RAILS_LOG_TO_STDOUT" = "enabled"
  }
}

resource "kubernetes_deployment" "webapp" {
  metadata {
    name = "webapp"
    namespace = kubernetes_namespace.pseudonymisation_service.id
    labels = {
      app = "pseudonymisation-service"
      tier = "web"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "pseudonymisation-service"
        tier = "web"
      }
    }
    template {
      metadata {
        labels = {
          app = "pseudonymisation-service"
          tier = "web"
        }
      }
      spec {
        container {
          image = "ghcr.io/joshpencheon/pseudonymisation_service:${var.release_tag}"
          name = "webapp"

          port {
            container_port = 80
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.webapp.metadata[0].name
            }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
          }

          lifecycle {
            post_start {
              exec {
                command = [
                  "/bin/sh",
                  "-c",
                  "RAILS_ENV=production rails db:create db:migrate db:seed"
                ]
              }
            }
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
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "pseudonymisation_service_web_policy" {
  metadata {
    name = "pseudonymisation-service-web-policy"
    namespace = kubernetes_namespace.pseudonymisation_service.id
  }

  spec {
    pod_selector {
      match_labels = {
        app  = kubernetes_deployment.webapp.metadata[0].labels.app
        tier = kubernetes_deployment.webapp.metadata[0].labels.tier
      }
    }

    # Allow connections out the the DB:
    egress {
      ports {
        port     = "5432"
        protocol = "TCP"
      }

      to {
        pod_selector {
          match_labels = {
            app  = kubernetes_deployment.postgres.metadata[0].labels.app
            tier = kubernetes_deployment.postgres.metadata[0].labels.tier
          }
        }
      }
    }

    # Allow connections to DNS (and anything else on :53):
    egress {
      ports {
        port     = "53"
        protocol = "TCP"
      }

      ports {
        port     = "53"
        protocol = "UDP"
      }
    }

    policy_types = ["Egress"]
  }
}

resource "kubernetes_service" "webapp" {
  metadata {
    name = "webapp"
    namespace = kubernetes_namespace.pseudonymisation_service.id
    labels = {
      app = "pseudonymisation-service"
    }
  }

  spec {
    selector = {
      app  = kubernetes_deployment.webapp.metadata[0].labels.app
      tier = kubernetes_deployment.webapp.metadata[0].labels.tier
    }

    port {
      port = 80
      target_port = 3000
    }

    type = "NodePort"
  }
}

resource "kubernetes_ingress" "webapp" {
  metadata {
    name = "webapp"
    namespace = kubernetes_namespace.pseudonymisation_service.id
    labels = {
      app = "pseudonymisation-service"
    }
  }

  spec {
    rule {
      host = "${var.label}.pseudonymise.test"
      http {
        path {
          path = "/"
          backend {
            service_name = kubernetes_service.webapp.metadata[0].name
            service_port = kubernetes_service.webapp.spec[0].port[0].port
          }
        }
      }
    }
  }
}
