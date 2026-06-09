variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "location" {
  description = "Azure region for the storage account."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group hosting the storage account."
  type        = string
}

variable "tags" {
  description = "Common tags to apply."
  type        = map(string)
  default     = {}
}

variable "blob_storage_enabled" {
  description = "If true, creates the Azure Storage Account for blob storage."
  type        = bool
  default     = false
}
