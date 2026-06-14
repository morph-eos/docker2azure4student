variable "subscription_id" {
  description = "Subscription ID to use. Leave empty to rely on Azure CLI or environment authentication."
  type        = string
  default     = null
}

variable "tenant_id" {
  description = "Tenant ID to use. Leave empty to rely on Azure CLI or environment authentication."
  type        = string
  default     = null
}

variable "log_max_total_gb" {
  description = "Soft cap on total Log Analytics size in GB (enforced as a daily ingestion quota). Set to -1 to disable the cap."
  type        = number
  default     = 3
}

variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "francecentral"
}

variable "environment_name" {
  description = "Human readable environment or project name (used as prefix for resources)."
  type        = string
  default     = "student-app"
}

variable "tags" {
  description = "Common tags to apply to Azure resources."
  type        = map(string)
  default = {
    environment = "student"
    managed_by  = "terraform"
  }
}

variable "vm_size" {
  description = "Azure VM size hosting the container workload."
  type        = string
  default     = "Standard_B1s"
}

variable "vm_admin_username" {
  description = "Admin username configured on the Linux VM."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key that will be allowed to connect to the VM."
  type        = string
}

variable "vm_http_port" {
  description = "Public HTTP port exposed on the VM."
  type        = number
  default     = 80
}

variable "vm_https_port" {
  description = "Public HTTPS port exposed on the VM."
  type        = number
  default     = 443
}

variable "vm_public_ip_static" {
  description = "If true, allocates a static public IP for the VM. This is required for database connectivity: PostgreSQL is firewalled to the VM's IP only, and a static IP keeps that allow-list rule valid across VM stop/start. Disabling it removes the DB firewall rule and the app will not be able to reach PostgreSQL."
  type        = bool
  default     = true
}

variable "automation_location" {
  description = "Region used to host Azure Automation (defaults to an allowed Student-plan region)."
  type        = string
  default     = "eastus"
}

variable "vm_schedule_enabled" {
  description = "If true, automatically stop/start the VM on a daily schedule to save costs."
  type        = bool
  default     = false
}

variable "vm_schedule_timezone" {
  description = "Timezone used for the VM daily schedule (IANA/Windows compatible)."
  type        = string
  default     = "Europe/Rome"
}

variable "vm_schedule_start_time" {
  description = "Time of day (HH:MM) when the VM should be started."
  type        = string
  default     = "07:00"
}

variable "vm_schedule_stop_time" {
  description = "Time of day (HH:MM) when the VM should be stopped."
  type        = string
  default     = "19:00"
}

variable "db_admin_username" {
  description = "Username for the managed PostgreSQL server."
  type        = string
  default     = "pgadmin"
}

variable "db_admin_password" {
  description = "Password for the managed PostgreSQL server."
  type        = string
  sensitive   = true
}

variable "db_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "db_storage_mb" {
  description = "Storage allocated to the PostgreSQL flexible server (in MB)."
  type        = number
  default     = 32768
}

variable "db_auto_grow_enabled" {
  description = "Whether the PostgreSQL storage should auto-grow beyond the configured size (disabling it keeps you safely in the free tier)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Number of days to retain automatic backups."
  type        = number
  default     = 7
}

variable "db_zone" {
  description = "Availability zone used by the PostgreSQL flexible server."
  type        = string
  default     = "1"
}

variable "db_backup_enabled" {
  description = "Enable Automation runbook that triggers an on-demand PostgreSQL backup once per day."
  type        = bool
  default     = true
}

variable "db_backup_time" {
  description = "Time of day (HH:MM) when the on-demand PostgreSQL backup should run."
  type        = string
  default     = "20:30"
}

variable "db_backup_timezone" {
  description = "Timezone for the PostgreSQL backup automation schedule."
  type        = string
  default     = "Europe/Rome"
}

variable "vm_snapshot_runbook_enabled" {
  description = "Deploys an Automation runbook to create manual snapshots of the VM OS disk."
  type        = bool
  default     = true
}

variable "vm_snapshot_cleanup_enabled" {
  description = "Enables the Automation workflow that deletes VM snapshots older than the retention window."
  type        = bool
  default     = true
}

variable "vm_snapshot_retention_days" {
  description = "Number of days to keep VM snapshots before the cleanup job removes them."
  type        = number
  default     = 90
}

variable "vm_snapshot_cleanup_time" {
  description = "Time of day (HH:MM) when the snapshot cleanup automation should run."
  type        = string
  default     = "03:00"
}

variable "vm_snapshot_cleanup_timezone" {
  description = "Timezone used by the snapshot cleanup schedule."
  type        = string
  default     = "Europe/Rome"
}

variable "allowed_admin_cidrs" {
  description = "List of IPv4 CIDR ranges allowed to SSH/HTTP/HTTPS into the VM."
  type        = list(string)
  default     = []
}

variable "blob_storage_enabled" {
  description = "If true, creates an Azure Storage Account for blob storage. The account name and primary key are exported as outputs and injected into the application environment as AZURE_ACCOUNT_NAME and AZURE_ACCOUNT_KEY."
  type        = bool
  default     = false
}
