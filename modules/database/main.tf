resource "random_string" "db_suffix" {
  length  = 5
  special = false
  upper   = false

  lifecycle {
    ignore_changes = [special, upper]
  }
}

resource "azurerm_postgresql_flexible_server" "db" {
  name                          = "${var.name_prefix}-pg-${random_string.db_suffix.result}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.db_version
  administrator_login           = var.db_admin_username
  administrator_password        = var.db_admin_password
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = var.db_storage_mb
  auto_grow_enabled             = var.db_auto_grow_enabled
  backup_retention_days         = var.db_backup_retention_days
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = true
  zone                          = var.db_zone

  tags = merge(var.tags, { component = "database" })
}

resource "azurerm_postgresql_flexible_server_database" "app_db" {
  name      = "postgres"
  server_id = azurerm_postgresql_flexible_server.db.id
}

# The PostgreSQL endpoint stays public but is firewalled to a single IP: the
# VM's static public IP. The previous "allow-azure-services" rule (0.0.0.0) was
# removed because, on a Flexible Server, it actually allows ANY Azure tenant to
# connect — not just this deployment. Reaching the DB now requires the VM to have
# a static public IP (vm_public_ip_static = true), which is the default.
resource "azurerm_postgresql_flexible_server_firewall_rule" "vm_public_ip" {
  count     = var.vm_public_ip_static ? 1 : 0
  name      = "allow-vm"
  server_id = azurerm_postgresql_flexible_server.db.id

  start_ip_address = var.vm_public_ip_address
  end_ip_address   = var.vm_public_ip_address
}
