locals {
  normalized_name = lower(replace(var.environment_name, " ", "-"))
  prefix          = substr(local.normalized_name, 0, 45)
}
