locals {
  # The daily ingestion quota (GB) that keeps the workspace at max_total_gb over
  # the retention window, or -1 when the cap is off.
  daily_quota_gb = var.max_total_gb > 0 ? var.max_total_gb / var.retention_days : -1
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_days

  # Keep cost/size modest: cap daily ingestion so total stays ~<= max_total_gb
  # over the retention window. -1 disables the cap. The cap counts what arrives
  # per day, not what is stored: old data is deleted by the retention setting.
  daily_quota_gb = local.daily_quota_gb

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

# Route resource logs into the workspace. PostgreSQL sends only its server log:
# the session, table and transaction statistics categories and a copy of the
# platform metrics add volume against the daily cap and nothing reads them (the
# database alerts use the platform metrics directly).
resource "azurerm_monitor_diagnostic_setting" "postgres" {
  name                       = "to-law"
  target_resource_id         = var.postgres_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "PostgreSQLLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "to-law"
  target_resource_id         = var.key_vault_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# E-mail logs of Azure Communication Services: one row per send request and one
# per delivery status, to see what happened to a given message. Optional because
# the resource is not part of this template.
resource "azurerm_monitor_diagnostic_setting" "communication" {
  count                      = var.communication_service_id == "" ? 0 : 1
  name                       = "to-law"
  target_resource_id         = var.communication_service_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "EmailSendMailOperational"
  }

  enabled_log {
    category = "EmailStatusUpdateOperational"
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

# Low-memory alert on the VM host metric (no agent needed). Metric alert rules
# and an email-only action group cost a negligible amount. Notifications go to
# every Owner of the subscription, plus var.alert_email when set.
resource "azurerm_monitor_action_group" "ops" {
  name                = "${var.name_prefix}-ops"
  resource_group_name = var.resource_group_name
  short_name          = "locus-ops"

  arm_role_receiver {
    name                    = "subscription-owners"
    role_id                 = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635" # Owner
    use_common_alert_schema = true
  }

  dynamic "email_receiver" {
    for_each = var.alert_email == "" ? [] : [var.alert_email]
    content {
      name                    = "ops"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  tags = merge(var.tags, { component = "monitoring" })
}

resource "azurerm_monitor_metric_alert" "vm_memory_low" {
  name                = "${var.name_prefix}-vm-memory-low"
  resource_group_name = var.resource_group_name
  scopes              = [var.vm_id]
  description         = "VM available memory is below ${var.memory_alert_threshold_mb} MB."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Available Memory Bytes"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.memory_alert_threshold_mb * 1024 * 1024
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = merge(var.tags, { component = "monitoring" })
}
