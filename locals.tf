locals {
  normalized_name = lower(replace(var.environment_name, " ", "-"))
  prefix          = substr(local.normalized_name, 0, 45)
  public_ip_name  = "${local.prefix}-vm-ip-${var.vm_public_ip_static ? "static" : "dynamic"}"

  schedule_anchor_timestamp     = timeadd(timestamp(), "24h")
  schedule_anchor_date          = formatdate("YYYY-MM-DD", local.schedule_anchor_timestamp)
  vm_start_timestamp            = "${local.schedule_anchor_date}T${var.vm_schedule_start_time}:00Z"
  vm_stop_timestamp             = "${local.schedule_anchor_date}T${var.vm_schedule_stop_time}:00Z"
  db_backup_timestamp           = "${local.schedule_anchor_date}T${var.db_backup_time}:00Z"
  vm_snapshot_cleanup_timestamp = "${local.schedule_anchor_date}T${var.vm_snapshot_cleanup_time}:00Z"

  automation_required = var.vm_schedule_enabled || var.db_backup_enabled || var.vm_snapshot_runbook_enabled || var.vm_snapshot_cleanup_enabled
  subscription_id     = coalesce(var.subscription_id, data.azurerm_client_config.current.subscription_id)
}
