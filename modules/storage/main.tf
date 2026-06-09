resource "random_string" "blob_suffix" {
  count   = var.blob_storage_enabled ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "blob" {
  count                           = var.blob_storage_enabled ? 1 : 0
  name                            = "${substr(replace(var.name_prefix, "-", ""), 0, 18)}${random_string.blob_suffix[0].result}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  tags = merge(var.tags, { component = "storage" })
}
