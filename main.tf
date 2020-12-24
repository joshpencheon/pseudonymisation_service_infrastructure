terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }

    github = {
      source = "hashicorp/github"
    }
  }
}

provider "kubernetes" {}

provider "github" {
  owner = "joshpencheon"
  # token = "..." <- required, but can be read from $GITHUB_TOKEN
}

locals {
  branch      = terraform.workspace
  release_tag = coalesce(var.release_tag, data.github_branch.current.sha)
}

data "github_branch" "current" {
  repository = "pseudonymisation_service"
  branch     = local.branch
}

module "pseudo_service" {
  source = "./modules/pseudo-service"

  label       = local.branch
  release_tag = local.release_tag
}
