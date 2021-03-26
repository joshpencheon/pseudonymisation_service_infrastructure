variable "release_tag" {
  type        = string
  description = "The image tag to deploy." 
}

variable "label" {
  type        = string
  description = "The identifier of the deployment. Used to name the Namespace, and the Ingress route"
}

variable "use_shared_db" {
  type        = bool
  description = "Whether to use a shared PG database, or deploy an ephemeral DB. Both will be migrated."
}
