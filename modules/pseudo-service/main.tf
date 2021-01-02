resource "kubernetes_namespace" "pseudonymisation_service" {
  metadata {
    name = "pseudonymisation-service-${var.label}"
  }
}

resource "kubernetes_persistent_volume_claim" "postgres" {
  metadata {
    name = "postgres-data-volume-claim"
    namespace = kubernetes_namespace.pseudonymisation_service.id
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
      app = "pseudo-db"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "pseudo-db"
      }
    }
    template {
      metadata {
        labels = {
          app = "pseudo-db"
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


resource "kubernetes_service" "postgres" {
  metadata {
    name = "db"
    namespace = kubernetes_namespace.pseudonymisation_service.id
  }

  spec {
    selector = {
      app = kubernetes_deployment.postgres.metadata[0].labels.app
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
      app = "pseudo-app"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "pseudo-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "pseudo-app"
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


resource "kubernetes_service" "webapp" {
  metadata {
    name = "webapp"
    namespace = kubernetes_namespace.pseudonymisation_service.id
  }

  spec {
    selector = {
      app = kubernetes_deployment.webapp.metadata[0].labels.app
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
