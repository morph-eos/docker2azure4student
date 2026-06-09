variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "automation_location" {
  description = "Region used to host Azure Automation."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group hosting the automation resources."
  type        = string
}

variable "resource_group_id" {
  description = "ID of the resource group (role assignment scope)."
  type        = string
}

variable "tags" {
  description = "Common tags to apply."
  type        = map(string)
  default     = {}
}

variable "subscription_id" {
  description = "Subscription ID used by the database backup runbook."
  type        = string
}

variable "vm_name" {
  description = "Name of the VM targeted by the start/stop/snapshot runbooks."
  type        = string
}

variable "db_server_name" {
  description = "Name of the PostgreSQL server targeted by the backup runbook."
  type        = string
  default     = ""
}

variable "vm_schedule_enabled" {
  description = "If true, schedules daily VM start/stop."
  type        = bool
}

variable "vm_schedule_timezone" {
  description = "Timezone used for the VM daily schedule."
  type        = string
}

variable "vm_schedule_start_time" {
  description = "Time of day (HH:MM) when the VM should be started."
  type        = string
}

variable "vm_schedule_stop_time" {
  description = "Time of day (HH:MM) when the VM should be stopped."
  type        = string
}

variable "db_backup_enabled" {
  description = "If true, schedules a daily on-demand PostgreSQL backup."
  type        = bool
}

variable "db_backup_timezone" {
  description = "Timezone for the PostgreSQL backup automation schedule."
  type        = string
}

variable "db_backup_time" {
  description = "Time of day (HH:MM) when the PostgreSQL backup should run."
  type        = string
}

variable "vm_snapshot_runbook_enabled" {
  description = "Deploys the runbook to create manual VM snapshots."
  type        = bool
}

variable "vm_snapshot_cleanup_enabled" {
  description = "Enables the workflow that deletes old VM snapshots."
  type        = bool
}

variable "vm_snapshot_cleanup_timezone" {
  description = "Timezone used by the snapshot cleanup schedule."
  type        = string
}

variable "vm_snapshot_cleanup_time" {
  description = "Time of day (HH:MM) when the snapshot cleanup should run."
  type        = string
}

variable "vm_snapshot_retention_days" {
  description = "Number of days to keep VM snapshots before cleanup."
  type        = number
}
