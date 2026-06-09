variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "location" {
  description = "Azure region for the VM."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group hosting the VM."
  type        = string
}

variable "tags" {
  description = "Common tags to apply."
  type        = map(string)
  default     = {}
}

variable "vm_size" {
  description = "Azure VM size hosting the container workload."
  type        = string
}

variable "vm_admin_username" {
  description = "Admin username configured on the Linux VM."
  type        = string
}

variable "admin_ssh_public_key" {
  description = "SSH public key allowed to connect to the VM."
  type        = string
}

variable "network_interface_id" {
  description = "ID of the network interface to attach to the VM."
  type        = string
}
