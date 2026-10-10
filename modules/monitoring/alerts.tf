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

# Availability test from outside Azure. With the SSL check on, the test also
# fails once the certificate has under 14 days left, which is how an expired
# or unrenewed certificate gets noticed.
resource "azurerm_application_insights_standard_web_test" "site" {
  count                   = var.site_url == "" ? 0 : 1
  name                    = "${var.name_prefix}-site-availability"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.main.id
  geo_locations           = ["emea-nl-ams-azr"]
  frequency               = 600
  timeout                 = 30
  enabled                 = true

  request {
    url                      = var.site_url
    follow_redirects_enabled = true
  }

  validation_rules {
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 14
  }

  tags = merge(var.tags, {
    component                                             = "monitoring"
    "hidden-link:${azurerm_application_insights.main.id}" = "Resource"
  })
}

resource "azurerm_monitor_metric_alert" "site_unavailable" {
  count               = var.site_url == "" ? 0 : 1
  name                = "${var.name_prefix}-site-unavailable"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_application_insights.main.id, azurerm_application_insights_standard_web_test.site[0].id]
  description         = "The public site is unreachable from the test location, or its TLS certificate expires within 14 days."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.site[0].id
    component_id          = azurerm_application_insights.main.id
    failed_location_count = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = merge(var.tags, { component = "monitoring" })
}
