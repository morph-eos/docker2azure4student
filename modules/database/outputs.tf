output "server_id" {
  description = "ID of the PostgreSQL flexible server."
  value       = azurerm_postgresql_flexible_server.db.id
}

output "server_name" {
  description = "Name of the PostgreSQL flexible server."
  value       = azurerm_postgresql_flexible_server.db.name
}

output "fqdn" {
  description = "Fully qualified domain name of the PostgreSQL server."
  value       = azurerm_postgresql_flexible_server.db.fqdn
}

output "database_name" {
  description = "Name of the application database."
  value       = azurerm_postgresql_flexible_server_database.app_db.name
}
