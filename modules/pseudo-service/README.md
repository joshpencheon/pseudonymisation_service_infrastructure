# Module: pseudo-service

An expermental module for setting up a skeleton stack for the Pseudonymisation Service, within Kubernetes.

## Usage

```
module "pseudo_service" {
  source = "./modules/pseudo-service"

  release_tag = "latest" # The default. Or supply any commit SHA used to tag an image.
  
  label = "feature123" # Defaults to the branch name. Used for Egress configuration.

  use_shared_db = false # Deploy connected to a shared PG instance, or to a dedicated ephemeral instance
}
```
