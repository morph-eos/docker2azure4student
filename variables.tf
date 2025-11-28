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
  default     = "Standard_B1ms"
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

variable "db_backup_retention_days" {
  description = "Number of days to retain automatic backups."
  type        = number
  default     = 7
}

variable "allowed_admin_cidrs" {
  description = "List of IPv4 CIDR ranges allowed to SSH/HTTP/HTTPS into the VM."
  type        = list(string)
  default     = []
}
