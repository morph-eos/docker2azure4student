# Metric alerts beyond the VM memory one (main.tf). All notify the shared
# action group.

locals {
  db_alerts = {
    storage = {
      metric    = "storage_percent"
      threshold = 85
      window    = "PT15M"
      summary   = "database storage is above 85%"
    }
    cpu = {
      metric    = "cpu_percent"
      threshold = 90
      window    = "PT30M"
      summary   = "database CPU has been above 90% for 30 minutes"
    }
  }
}

resource "azurerm_monitor_metric_alert" "db" {
  for_each            = local.db_alerts
  name                = "${var.name_prefix}-db-${each.key}"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgres_id]
  description         = "PostgreSQL: ${each.value.summary}."
  severity            = 2
  frequency           = "PT5M"
  window_size         = each.value.window

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = each.value.metric
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = each.value.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = merge(var.tags, { component = "monitoring" })
}

resource "azurerm_monitor_metric_alert" "automation_job_failed" {
  count               = var.automation_enabled ? 1 : 0
  name                = "${var.name_prefix}-automation-job-failed"
  resource_group_name = var.resource_group_name
  scopes              = [var.automation_account_id]
  description         = "An Automation runbook job (snapshot, cleanup, schedule or backup) failed or was suspended."
  severity            = 2
  frequency           = "PT15M"
  window_size         = "PT1H"

  criteria {
    metric_namespace = "Microsoft.Automation/automationAccounts"
    metric_name      = "TotalJob"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Failed", "Suspended"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = merge(var.tags, { component = "monitoring" })
}
