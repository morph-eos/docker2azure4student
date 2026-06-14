output "workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.main.id
}

output "app_insights_id" {
  description = "Resource ID of the Application Insights component."
  value       = azurerm_application_insights.main.id
}

output "connection_string" {
  description = "Application Insights connection string for the app SDK."
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}
