output "account_name" {
  description = "Name of the Azure Storage Account (null when blob_storage_enabled = false)."
  value       = var.blob_storage_enabled ? azurerm_storage_account.blob[0].name : null
}

output "primary_access_key" {
  description = "Primary access key for the Azure Storage Account (null when blob_storage_enabled = false)."
  value       = var.blob_storage_enabled ? azurerm_storage_account.blob[0].primary_access_key : null
  sensitive   = true
}
