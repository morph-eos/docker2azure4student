resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_days

  # Keep cost/size modest: cap daily ingestion so total stays ~<= max_total_gb
  # over the retention window. -1 disables the cap.
  daily_quota_gb = var.max_total_gb > 0 ? var.max_total_gb / var.retention_days : -1

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

# Observability workbook (free): requests, exceptions, traces over App Insights.
resource "random_uuid" "workbook" {}

resource "azurerm_application_insights_workbook" "observability" {
  name                = random_uuid.workbook.result
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "${var.name_prefix} observability"
  source_id           = lower(azurerm_application_insights.main.id)

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type    = 1
        content = { json = "## ${var.name_prefix} — requests, exceptions, traces" }
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "AppRequests | summarize total=count(), failed=countif(Success == false) by bin(TimeGenerated, 5m) | render timechart"
          size         = 0
          title        = "Requests"
          queryType    = 0
          resourceType = "microsoft.insights/components"
        }
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "AppExceptions | summarize count() by ProblemId | order by count_ desc | take 20"
          size         = 0
          title        = "Exceptions"
          queryType    = 0
          resourceType = "microsoft.insights/components"
        }
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "AppTraces | where SeverityLevel >= 2 | project TimeGenerated, SeverityLevel, Message | order by TimeGenerated desc | take 50"
          size         = 0
          title        = "Traces"
          queryType    = 0
          resourceType = "microsoft.insights/components"
        }
      }
    ]
  })

  tags = merge(var.tags, { component = "monitoring" })
}
