variable "release_tag" {
  type    = string
  default = ""
}

variable "use_shared_db" {
  description = "If set to true, enable connect to a shared PG cluster"
  type        = bool
  default     = false
}
