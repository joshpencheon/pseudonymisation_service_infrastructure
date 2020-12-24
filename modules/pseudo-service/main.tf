resource "kubernetes_namespace" "pseudonymisation_service" {
  metadata {
    name = "pseudonymisation-service-${var.label}"
  }
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
          image = "postgres"
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

          env {
            name = "DATABASE_HOST"
            value = "db"
          }

          env {
            name = "DATABASE_USERNAME"
            value = "postgres"
          }

          env {
            name = "DATABASE_PASSWORD"
            value = "password"
          }

          env {
            name = "RAILS_ENV"
            value = "production"
          }

          env {
            name = "RAILS_LOG_TO_STDOUT"
            value = "enabled"
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
