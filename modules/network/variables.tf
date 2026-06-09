variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "location" {
  description = "Azure region for the network resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group hosting the network resources."
  type        = string
}

variable "tags" {
  description = "Common tags to apply."
  type        = map(string)
  default     = {}
}

variable "vm_http_port" {
  description = "Public HTTP port exposed on the VM."
  type        = number
}

variable "vm_https_port" {
  description = "Public HTTPS port exposed on the VM."
  type        = number
}

variable "allowed_admin_cidrs" {
  description = "IPv4 CIDR ranges allowed to SSH into the VM."
  type        = list(string)
  default     = []
}

variable "vm_public_ip_static" {
  description = "If true, allocates a static public IP instead of dynamic."
  type        = bool
  default     = false
}
