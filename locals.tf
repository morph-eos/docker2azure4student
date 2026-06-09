locals {
  normalized_name = lower(replace(var.environment_name, " ", "-"))
  prefix          = substr(local.normalized_name, 0, 45)
  subscription_id = coalesce(var.subscription_id, data.azurerm_client_config.current.subscription_id)
}
