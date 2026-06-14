resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_days

  tags = merge(var.tags, { component = "monitoring" })
}

# Workspace-based Application Insights (app telemetry lands in the workspace).
resource "azurerm_application_insights" "main" {
  name                = "${var.name_prefix}-appi"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = merge(var.tags, { component = "monitoring" })
}

# Route resource logs + metrics into the workspace.
resource "azurerm_monitor_diagnostic_setting" "postgres" {
  name                       = "to-law"
  target_resource_id         = var.postgres_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "to-law"
  target_resource_id         = var.key_vault_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "audit"
  }

  metric {
    category = "AllMetrics"
  }
}
