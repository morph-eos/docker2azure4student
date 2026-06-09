variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "location" {
  description = "Azure region for the database."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group hosting the database."
  type        = string
}

variable "tags" {
  description = "Common tags to apply."
  type        = map(string)
  default     = {}
}

variable "db_admin_username" {
  description = "Username for the managed PostgreSQL server."
  type        = string
}

variable "db_admin_password" {
  description = "Password for the managed PostgreSQL server."
  type        = string
  sensitive   = true
}

variable "db_version" {
  description = "PostgreSQL major version."
  type        = string
}

variable "db_storage_mb" {
  description = "Storage allocated to the PostgreSQL flexible server (in MB)."
  type        = number
}

variable "db_auto_grow_enabled" {
  description = "Whether the PostgreSQL storage should auto-grow."
  type        = bool
}

variable "db_backup_retention_days" {
  description = "Number of days to retain automatic backups."
  type        = number
}

variable "db_zone" {
  description = "Availability zone used by the PostgreSQL flexible server."
  type        = string
}

variable "vm_public_ip_static" {
  description = "If true, a firewall rule for the VM public IP is created."
  type        = bool
  default     = false
}

variable "vm_public_ip_address" {
  description = "Public IP address of the VM (used by the firewall rule when static)."
  type        = string
  default     = null
}
