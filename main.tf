data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = "${local.prefix}-rg"
  location = var.location
  tags     = var.tags
}

module "network" {
  source              = "./modules/network"
  name_prefix         = local.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  vm_http_port        = var.vm_http_port
  vm_https_port       = var.vm_https_port
  allowed_admin_cidrs = var.allowed_admin_cidrs
  vm_public_ip_static = var.vm_public_ip_static
}

module "compute" {
  source               = "./modules/compute"
  name_prefix          = local.prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.main.name
  tags                 = var.tags
  vm_size              = var.vm_size
  vm_admin_username    = var.vm_admin_username
  admin_ssh_public_key = var.admin_ssh_public_key
  network_interface_id = module.network.network_interface_id
}

module "database" {
  source                   = "./modules/database"
  name_prefix              = local.prefix
  location                 = var.location
  resource_group_name      = azurerm_resource_group.main.name
  tags                     = var.tags
  db_admin_username        = var.db_admin_username
  db_admin_password        = var.db_admin_password
  db_version               = var.db_version
  db_storage_mb            = var.db_storage_mb
  db_auto_grow_enabled     = var.db_auto_grow_enabled
  db_backup_retention_days = var.db_backup_retention_days
  db_zone                  = var.db_zone
  vm_public_ip_static      = var.vm_public_ip_static
  vm_public_ip_address     = module.network.public_ip_address
}

module "automation" {
  source                       = "./modules/automation"
  name_prefix                  = local.prefix
  automation_location          = var.automation_location
  resource_group_name          = azurerm_resource_group.main.name
  resource_group_id            = azurerm_resource_group.main.id
  tags                         = var.tags
  subscription_id              = local.subscription_id
  vm_name                      = module.compute.vm_name
  db_server_name               = module.database.server_name
  vm_schedule_enabled          = var.vm_schedule_enabled
  vm_schedule_timezone         = var.vm_schedule_timezone
  vm_schedule_start_time       = var.vm_schedule_start_time
  vm_schedule_stop_time        = var.vm_schedule_stop_time
  db_backup_enabled            = var.db_backup_enabled
  db_backup_timezone           = var.db_backup_timezone
  db_backup_time               = var.db_backup_time
  vm_snapshot_runbook_enabled  = var.vm_snapshot_runbook_enabled
  vm_snapshot_cleanup_enabled  = var.vm_snapshot_cleanup_enabled
  vm_snapshot_cleanup_timezone = var.vm_snapshot_cleanup_timezone
  vm_snapshot_cleanup_time     = var.vm_snapshot_cleanup_time
  vm_snapshot_retention_days   = var.vm_snapshot_retention_days
}

module "storage" {
  source               = "./modules/storage"
  name_prefix          = local.prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.main.name
  tags                 = var.tags
  blob_storage_enabled = var.blob_storage_enabled
}
