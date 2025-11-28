resource "azurerm_resource_group" "main" {
  name     = "${local.prefix}-rg"
  location = var.location
  tags     = var.tags
}

resource "random_string" "db_suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.prefix}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.10.0.0/16"]
  tags                = merge(var.tags, { component = "network" })
}

resource "azurerm_subnet" "vm" {
  name                 = "${local.prefix}-vm-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_network_security_group" "vm" {
  name                = "${local.prefix}-vm-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.vm_http_port)
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.vm_https_port)
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-egress"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = merge(var.tags, { component = "network" })
}

resource "azurerm_network_security_rule" "ssh" {
  for_each                    = zipmap(var.allowed_admin_cidrs, range(length(var.allowed_admin_cidrs)))
  name                        = "allow-ssh-${replace(each.key, "/", "-")}"
  priority                    = 200 + each.value
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = each.key
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.vm.name
}

resource "azurerm_public_ip" "vm" {
  name                = "${local.prefix}-vm-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Basic"
  tags                = merge(var.tags, { component = "network" })
}

resource "azurerm_network_interface" "vm" {
  name                = "${local.prefix}-vm-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }

  tags = merge(var.tags, { component = "network" })
}

resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_linux_virtual_machine" "app" {
  name                            = "${local.prefix}-vm"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.vm_admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm.id]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    name                 = "${local.prefix}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = merge(var.tags, { component = "compute" })
}

resource "azurerm_postgresql_flexible_server" "db" {
  name                          = "${local.prefix}-pg-${random_string.db_suffix.result}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  version                       = var.db_version
  administrator_login           = var.db_admin_username
  administrator_password        = var.db_admin_password
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = var.db_storage_mb
  backup_retention_days         = var.db_backup_retention_days
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = true

  tags = merge(var.tags, { component = "database" })
}

resource "azurerm_postgresql_flexible_server_database" "app_db" {
  name      = "appdb"
  server_id = azurerm_postgresql_flexible_server.db.id
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name      = "allow-azure-services"
  server_id = azurerm_postgresql_flexible_server.db.id

  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "vm_public_ip" {
  name      = "allow-vm"
  server_id = azurerm_postgresql_flexible_server.db.id

  start_ip_address = azurerm_public_ip.vm.ip_address
  end_ip_address   = azurerm_public_ip.vm.ip_address
}

