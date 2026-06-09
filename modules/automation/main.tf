locals {
  automation_required = var.vm_schedule_enabled || var.db_backup_enabled || var.vm_snapshot_runbook_enabled || var.vm_snapshot_cleanup_enabled

  schedule_anchor_timestamp     = timeadd(timestamp(), "24h")
  schedule_anchor_date          = formatdate("YYYY-MM-DD", local.schedule_anchor_timestamp)
  vm_start_timestamp            = "${local.schedule_anchor_date}T${var.vm_schedule_start_time}:00Z"
  vm_stop_timestamp             = "${local.schedule_anchor_date}T${var.vm_schedule_stop_time}:00Z"
  db_backup_timestamp           = "${local.schedule_anchor_date}T${var.db_backup_time}:00Z"
  vm_snapshot_cleanup_timestamp = "${local.schedule_anchor_date}T${var.vm_snapshot_cleanup_time}:00Z"
}

resource "azurerm_automation_account" "ops" {
  count               = local.automation_required ? 1 : 0
  name                = "${var.name_prefix}-aa"
  location            = var.automation_location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, { component = "automation" })
}

resource "azurerm_role_assignment" "automation_rg" {
  count                = local.automation_required ? 1 : 0
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.ops[0].identity[0].principal_id
}

resource "azurerm_automation_module" "az_accounts" {
  count                   = local.automation_required ? 1 : 0
  name                    = "Az.Accounts"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.ops[0].name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.Accounts/2.12.3"
  }
}

resource "azurerm_automation_module" "az_compute" {
  count                   = local.automation_required ? 1 : 0
  name                    = "Az.Compute"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.ops[0].name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.Compute/10.2.0"
  }
}

resource "azurerm_automation_module" "az_postgresql" {
  count                   = var.db_backup_enabled ? 1 : 0
  name                    = "Az.PostgreSql"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.ops[0].name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.PostgreSql/2.2.0"
  }
}

resource "azurerm_automation_runbook" "vm_start" {
  count                   = var.vm_schedule_enabled ? 1 : 0
  name                    = "${var.name_prefix}-start-vm"
  location                = var.automation_location
  resource_group_name     = var.resource_group_name
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
  name                    = "${var.name_prefix}-stop-vm"
  location                = var.automation_location
  resource_group_name     = var.resource_group_name
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
  name                    = "${var.name_prefix}-vm-start"
  resource_group_name     = var.resource_group_name
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
  name                    = "${var.name_prefix}-vm-stop"
  resource_group_name     = var.resource_group_name
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
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.ops[0].name
  runbook_name            = azurerm_automation_runbook.vm_start[0].name
  schedule_name           = azurerm_automation_schedule.vm_start[0].name

  parameters = {
    resourcegroupname = var.resource_group_name
    vmname            = var.vm_name
  }
}

resource "azurerm_automation_job_schedule" "vm_stop" {
  count                   = var.vm_schedule_enabled ? 1 : 0
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.ops[0].name
  runbook_name            = azurerm_automation_runbook.vm_stop[0].name
  schedule_name           = azurerm_automation_schedule.vm_stop[0].name

  parameters = {
    resourcegroupname = var.resource_group_name
    vmname            = var.vm_name
  }
}

resource "azurerm_automation_runbook" "db_backup" {
  count                   = var.db_backup_enabled ? 1 : 0
  name                    = "${var.name_prefix}-db-backup"
  location                = var.automation_location
  resource_group_name     = var.resource_group_name
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
  name                    = "${var.name_prefix}-snapshot"
  location                = var.automation_location
  resource_group_name     = var.resource_group_name
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
  name                    = "${var.name_prefix}-snapshot-cleanup"
  location                = var.automation_location
  resource_group_name     = var.resource_group_name
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
  name                    = "${var.name_prefix}-db-backup"
  resource_group_name     = var.resource_group_name
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
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.ops[0].name
  runbook_name            = azurerm_automation_runbook.db_backup[0].name
  schedule_name           = azurerm_automation_schedule.db_backup[0].name

  parameters = {
    subscriptionid    = var.subscription_id
    resourcegroupname = var.resource_group_name
    servername        = var.db_server_name
  }
}

resource "azurerm_automation_schedule" "vm_snapshot_cleanup" {
  count                   = var.vm_snapshot_cleanup_enabled ? 1 : 0
  name                    = "${var.name_prefix}-snapshot-cleanup"
  resource_group_name     = var.resource_group_name
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
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.ops[0].name
  runbook_name            = azurerm_automation_runbook.vm_snapshot_cleanup[0].name
  schedule_name           = azurerm_automation_schedule.vm_snapshot_cleanup[0].name

  parameters = {
    resourcegroupname = var.resource_group_name
    snapshotprefix    = "manual"
    retentiondays     = tostring(var.vm_snapshot_retention_days)
  }
}
