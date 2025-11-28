output "resource_group_name" {
  description = "Name of the resource group hosting every resource."
  value       = azurerm_resource_group.main.name
}

output "vm_public_ip" {
  description = "Public IP address of the VM exposing the containerized app."
  value       = azurerm_public_ip.vm.ip_address
}

output "ssh_connection_string" {
  description = "Convenience SSH command to access the VM."
  value       = "ssh ${var.vm_admin_username}@${azurerm_public_ip.vm.ip_address}"
}

output "database_fqdn" {
  description = "Fully qualified domain name of the managed PostgreSQL server."
  value       = azurerm_postgresql_flexible_server.db.fqdn
}

output "database_connection_string" {
  description = "PostgreSQL connection string for the container and external clients."
  sensitive   = true
  value       = "postgresql://${var.db_admin_username}:${var.db_admin_password}@${azurerm_postgresql_flexible_server.db.fqdn}:5432/${azurerm_postgresql_flexible_server_database.app_db.name}?sslmode=require"
}
