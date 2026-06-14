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

module "keyvault" {
  source                = "./modules/keyvault"
  name_prefix           = local.prefix
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  tenant_id             = data.azurerm_client_config.current.tenant_id
  tags                  = var.tags
  pipeline_principal_id = data.azurerm_client_config.current.object_id
  vm_principal_id       = module.compute.vm_principal_id
}

# First secret stored in Key Vault (Phase 1). The app still reads its config
# from the GitHub-secret-driven app.env for now; the VM-managed-identity read
# path is a later, verified phase.
resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "database-connection-string"
  value        = "postgresql://${var.db_admin_username}:${var.db_admin_password}@${module.database.fqdn}:5432/${module.database.database_name}?sslmode=require"
  key_vault_id = module.keyvault.key_vault_id

  depends_on = [module.keyvault]
}

# Storage account credentials in Key Vault (parity with the DB), created only
# when blob storage is enabled. The app receives them via app-env too.
resource "azurerm_key_vault_secret" "storage_account_name" {
  count        = var.blob_storage_enabled ? 1 : 0
  name         = "storage-account-name"
  value        = module.storage.account_name
  key_vault_id = module.keyvault.key_vault_id

  depends_on = [module.keyvault]
}

resource "azurerm_key_vault_secret" "storage_account_key" {
  count        = var.blob_storage_enabled ? 1 : 0
  name         = "storage-account-key"
  value        = module.storage.primary_access_key
  key_vault_id = module.keyvault.key_vault_id

  depends_on = [module.keyvault]
}

module "monitoring" {
  source              = "./modules/monitoring"
  name_prefix         = local.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  postgres_id         = module.database.server_id
  key_vault_id        = module.keyvault.key_vault_id
}

resource "azurerm_key_vault_secret" "appinsights_connection_string" {
  name         = "appinsights-connection-string"
  value        = module.monitoring.connection_string
  key_vault_id = module.keyvault.key_vault_id

  depends_on = [module.keyvault]
}
