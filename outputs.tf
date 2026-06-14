output "resource_group_name" {
  description = "Name of the resource group hosting every resource."
  value       = azurerm_resource_group.main.name
}

output "vm_public_ip" {
  description = "Public IP address of the VM exposing the containerized app."
  value       = module.network.public_ip_address
}

output "ssh_connection_string" {
  description = "Convenience SSH command to access the VM."
  value       = "ssh ${var.vm_admin_username}@${module.network.public_ip_address}"
}

output "database_fqdn" {
  description = "Fully qualified domain name of the managed PostgreSQL server."
  value       = module.database.fqdn
}

output "database_connection_string" {
  description = "PostgreSQL connection string for the container and external clients."
  sensitive   = true
  value       = "postgresql://${var.db_admin_username}:${var.db_admin_password}@${module.database.fqdn}:5432/${module.database.database_name}?sslmode=require"
}

output "storage_account_name" {
  description = "Name of the Azure Storage Account (null when blob_storage_enabled = false)."
  value       = module.storage.account_name
}

output "key_vault_name" {
  description = "Name of the Key Vault holding application secrets."
  value       = module.keyvault.key_vault_name
}

output "app_insights_connection_string" {
  description = "Application Insights connection string."
  value       = module.monitoring.connection_string
  sensitive   = true
}

output "storage_account_key" {
  description = "Primary access key for the Azure Storage Account (null when blob_storage_enabled = false)."
  sensitive   = true
  value       = module.storage.primary_access_key
}
