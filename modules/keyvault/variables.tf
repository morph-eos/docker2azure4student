variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group hosting the Key Vault."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant of the Key Vault."
  type        = string
}

variable "tags" {
  description = "Common tags to apply."
  type        = map(string)
  default     = {}
}

variable "pipeline_principal_id" {
  description = "Object ID of the principal running the pipeline (granted write access to secrets)."
  type        = string
}
