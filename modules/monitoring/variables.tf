variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "location" {
  description = "Azure region for the monitoring resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group hosting the monitoring resources."
  type        = string
}

variable "tags" {
  description = "Common tags to apply."
  type        = map(string)
  default     = {}
}

variable "retention_days" {
  description = "Log Analytics workspace retention in days."
  type        = number
  default     = 30
}

variable "postgres_id" {
  description = "Resource ID of the PostgreSQL server to route diagnostics from."
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault to route diagnostics from."
  type        = string
}
