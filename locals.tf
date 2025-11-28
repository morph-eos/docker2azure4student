locals {
  normalized_name = lower(replace(var.environment_name, " ", "-"))
  prefix          = substr(local.normalized_name, 0, 45)

  schedule_anchor_date = substr(time_static.schedule_anchor.rfc3339, 0, 10)
  vm_start_timestamp   = "${local.schedule_anchor_date}T${var.vm_schedule_start_time}:00"
  vm_stop_timestamp    = "${local.schedule_anchor_date}T${var.vm_schedule_stop_time}:00"
  vm_backup_timestamp  = "${local.schedule_anchor_date}T${var.vm_backup_time}:00"
  db_backup_timestamp  = "${local.schedule_anchor_date}T${var.db_backup_time}:00"

  automation_required = var.vm_schedule_enabled || var.db_backup_enabled
  subscription_id     = coalesce(var.subscription_id, data.azurerm_client_config.current.subscription_id)
}
