data "azurerm_client_config" "current" {}

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
  name                = local.public_ip_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = var.vm_public_ip_static ? "Static" : "Dynamic"
  sku                 = "Basic"
  tags                = merge(var.tags, { component = "network" })

  lifecycle {
    create_before_destroy = true
  }
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
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = merge(var.tags, { component = "compute" })
}

resource "azurerm_automation_account" "ops" {
  count               = local.automation_required ? 1 : 0
  name                = "${local.prefix}-aa"
  location            = var.automation_location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, { component = "automation" })
}

resource "azurerm_role_assignment" "automation_rg" {
  count                = local.automation_required ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.ops[0].identity[0].principal_id
}

resource "azurerm_automation_module" "az_accounts" {
  count                   = local.automation_required ? 1 : 0
  name                    = "Az.Accounts"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.Accounts/2.12.3"
  }
}

resource "azurerm_automation_module" "az_compute" {
  count                   = local.automation_required ? 1 : 0
  name                    = "Az.Compute"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.Compute/10.2.0"
  }
}

resource "azurerm_automation_module" "az_postgresql" {
  count                   = var.db_backup_enabled ? 1 : 0
  name                    = "Az.PostgreSql"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.PostgreSql/2.2.0"
  }
}

resource "azurerm_automation_runbook" "vm_start" {
  count                   = var.vm_schedule_enabled ? 1 : 0
  name                    = "${local.prefix}-start-vm"
  location                = var.automation_location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  content                 = <<-POWERSHELL
    param(
      [string]$resourceGroupName,
      [string]$vmName
    )

    Connect-AzAccount -Identity | Out-Null
    Start-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
  POWERSHELL

  depends_on = [
    azurerm_automation_module.az_accounts[0],
    azurerm_automation_module.az_compute[0]
  ]
}

resource "azurerm_automation_runbook" "vm_stop" {
  count                   = var.vm_schedule_enabled ? 1 : 0
  name                    = "${local.prefix}-stop-vm"
  location                = var.automation_location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  content                 = <<-POWERSHELL
    param(
      [string]$resourceGroupName,
      [string]$vmName
    )

    Connect-AzAccount -Identity | Out-Null
    Stop-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Force
  POWERSHELL

  depends_on = [
    azurerm_automation_module.az_accounts[0],
    azurerm_automation_module.az_compute[0]
  ]
}

resource "azurerm_automation_schedule" "vm_start" {
  count                   = var.vm_schedule_enabled ? 1 : 0
  name                    = "${local.prefix}-vm-start"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  frequency               = "Day"
  interval                = 1
  timezone                = var.vm_schedule_timezone
  start_time              = local.vm_start_timestamp

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_schedule" "vm_stop" {
  count                   = var.vm_schedule_enabled ? 1 : 0
  name                    = "${local.prefix}-vm-stop"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  frequency               = "Day"
  interval                = 1
  timezone                = var.vm_schedule_timezone
  start_time              = local.vm_stop_timestamp

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "vm_start" {
  count                   = var.vm_schedule_enabled ? 1 : 0
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  runbook_name            = azurerm_automation_runbook.vm_start[0].name
  schedule_name           = azurerm_automation_schedule.vm_start[0].name

  parameters = {
    resourcegroupname = azurerm_resource_group.main.name
    vmname            = azurerm_linux_virtual_machine.app.name
  }
}

resource "azurerm_automation_job_schedule" "vm_stop" {
  count                   = var.vm_schedule_enabled ? 1 : 0
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  runbook_name            = azurerm_automation_runbook.vm_stop[0].name
  schedule_name           = azurerm_automation_schedule.vm_stop[0].name

  parameters = {
    resourcegroupname = azurerm_resource_group.main.name
    vmname            = azurerm_linux_virtual_machine.app.name
  }
}

resource "azurerm_automation_runbook" "db_backup" {
  count                   = var.db_backup_enabled ? 1 : 0
  name                    = "${local.prefix}-db-backup"
  location                = var.automation_location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  content                 = <<-POWERSHELL
    param(
      [string]$subscriptionId,
      [string]$resourceGroupName,
      [string]$serverName
    )

    Connect-AzAccount -Identity | Out-Null

    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $uri = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.DBforPostgreSQL/flexibleServers/$serverName/createBackup?api-version=2024-08-01-preview"
    $body = @{ backup = @{ backupName = "manual-$timestamp" } } | ConvertTo-Json -Depth 5

    Invoke-AzRestMethod -Method POST -Path $uri -Payload $body | Out-Null
    Write-Output "Backup manuale creato: manual-$timestamp"
  POWERSHELL

  depends_on = [
    azurerm_automation_module.az_accounts[0],
    azurerm_automation_module.az_postgresql[0]
  ]
}

resource "azurerm_automation_runbook" "vm_snapshot" {
  count                   = var.vm_snapshot_runbook_enabled ? 1 : 0
  name                    = "${local.prefix}-snapshot"
  location                = var.automation_location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  description             = "Creates an on-demand snapshot of the VM OS disk"
  content                 = <<-POWERSHELL
    param(
      [string]$resourceGroupName,
      [string]$vmName,
      [string]$snapshotPrefix = "manual"
    )

    Connect-AzAccount -Identity | Out-Null

    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction Stop
    $osDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id
    $location = $vm.Location
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $snapshotName = "$snapshotPrefix-$timestamp"

    $snapshotConfig = New-AzSnapshotConfig -SourceResourceId $osDiskId -Location $location -CreateOption Copy
    New-AzSnapshot -Snapshot $snapshotConfig -ResourceGroupName $resourceGroupName -SnapshotName $snapshotName | Out-Null
    Write-Output "Snapshot created: $snapshotName"
  POWERSHELL

  depends_on = [
    azurerm_automation_module.az_accounts[0],
    azurerm_automation_module.az_compute[0]
  ]
}

resource "azurerm_automation_runbook" "vm_snapshot_cleanup" {
  count                   = var.vm_snapshot_cleanup_enabled ? 1 : 0
  name                    = "${local.prefix}-snapshot-cleanup"
  location                = var.automation_location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  description             = "Removes VM snapshots older than the configured retention window"
  content                 = <<-POWERSHELL
    param(
      [string]$resourceGroupName,
      [string]$snapshotPrefix = "manual",
      [int]$retentionDays = 90
    )

    Connect-AzAccount -Identity | Out-Null

    if ($retentionDays -le 0) {
      throw "RetentionDays must be greater than zero."
    }

    $cutoff = (Get-Date).AddDays(-1 * $retentionDays)
    $snapshots = Get-AzSnapshot -ResourceGroupName $resourceGroupName -ErrorAction Stop

    if ($snapshotPrefix) {
      $snapshots = $snapshots | Where-Object { $_.Name -like "$snapshotPrefix*" }
    }

    if (-not $snapshots) {
      Write-Output "No snapshots found matching the specified filters."
      return
    }

    $deleted = 0

    foreach ($snapshot in $snapshots) {
      if ($snapshot.TimeCreated -lt $cutoff) {
        Remove-AzSnapshot -ResourceGroupName $snapshot.ResourceGroupName -SnapshotName $snapshot.Name -Force
        $deleted++
        Write-Output "Deleted snapshot $($snapshot.Name) created on $($snapshot.TimeCreated)."
      }
    }

    if ($deleted -eq 0) {
      Write-Output "No snapshots older than $($cutoff.ToString('u')) were found."
    }
  POWERSHELL

  depends_on = [
    azurerm_automation_module.az_accounts[0],
    azurerm_automation_module.az_compute[0]
  ]
}

resource "azurerm_automation_schedule" "db_backup" {
  count                   = var.db_backup_enabled ? 1 : 0
  name                    = "${local.prefix}-db-backup"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  frequency               = "Day"
  interval                = 1
  timezone                = var.db_backup_timezone
  start_time              = local.db_backup_timestamp

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "db_backup" {
  count                   = var.db_backup_enabled ? 1 : 0
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  runbook_name            = azurerm_automation_runbook.db_backup[0].name
  schedule_name           = azurerm_automation_schedule.db_backup[0].name

  parameters = {
    subscriptionid    = local.subscription_id
    resourcegroupname = azurerm_resource_group.main.name
    servername        = azurerm_postgresql_flexible_server.db.name
  }
}

resource "azurerm_automation_schedule" "vm_snapshot_cleanup" {
  count                   = var.vm_snapshot_cleanup_enabled ? 1 : 0
  name                    = "${local.prefix}-snapshot-cleanup"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  frequency               = "Day"
  interval                = 1
  timezone                = var.vm_snapshot_cleanup_timezone
  start_time              = local.vm_snapshot_cleanup_timestamp

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "vm_snapshot_cleanup" {
  count                   = var.vm_snapshot_cleanup_enabled ? 1 : 0
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.ops[0].name
  runbook_name            = azurerm_automation_runbook.vm_snapshot_cleanup[0].name
  schedule_name           = azurerm_automation_schedule.vm_snapshot_cleanup[0].name

  parameters = {
    resourcegroupname = azurerm_resource_group.main.name
    snapshotprefix    = "manual"
    retentiondays     = tostring(var.vm_snapshot_retention_days)
  }
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
  auto_grow_enabled             = var.db_auto_grow_enabled
  backup_retention_days         = var.db_backup_retention_days
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = true
  zone                          = var.db_zone

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
  count     = var.vm_public_ip_static ? 1 : 0
  name      = "allow-vm"
  server_id = azurerm_postgresql_flexible_server.db.id

  start_ip_address = azurerm_public_ip.vm.ip_address
  end_ip_address   = azurerm_public_ip.vm.ip_address
}

