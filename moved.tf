# State migration for the monolith -> modules refactor.
# These blocks tell Terraform that resources changed ADDRESS (moved into a
# module) but are the SAME real resources, so they are NOT destroyed/recreated.
# An existing deployment that simply updates the repo keeps all its data.

# --- network ---
moved {
  from = azurerm_virtual_network.main
  to   = module.network.azurerm_virtual_network.main
}
moved {
  from = azurerm_subnet.vm
  to   = module.network.azurerm_subnet.vm
}
moved {
  from = azurerm_network_security_group.vm
  to   = module.network.azurerm_network_security_group.vm
}
moved {
  from = azurerm_network_security_rule.ssh
  to   = module.network.azurerm_network_security_rule.ssh
}
moved {
  from = azurerm_public_ip.vm
  to   = module.network.azurerm_public_ip.vm
}
moved {
  from = azurerm_network_interface.vm
  to   = module.network.azurerm_network_interface.vm
}
moved {
  from = azurerm_network_interface_security_group_association.vm
  to   = module.network.azurerm_network_interface_security_group_association.vm
}

# --- compute ---
moved {
  from = azurerm_linux_virtual_machine.app
  to   = module.compute.azurerm_linux_virtual_machine.app
}

# --- database ---
moved {
  from = random_string.db_suffix
  to   = module.database.random_string.db_suffix
}
moved {
  from = azurerm_postgresql_flexible_server.db
  to   = module.database.azurerm_postgresql_flexible_server.db
}
moved {
  from = azurerm_postgresql_flexible_server_database.app_db
  to   = module.database.azurerm_postgresql_flexible_server_database.app_db
}
moved {
  from = azurerm_postgresql_flexible_server_firewall_rule.azure_services
  to   = module.database.azurerm_postgresql_flexible_server_firewall_rule.azure_services
}
moved {
  from = azurerm_postgresql_flexible_server_firewall_rule.vm_public_ip
  to   = module.database.azurerm_postgresql_flexible_server_firewall_rule.vm_public_ip
}

# --- automation ---
moved {
  from = azurerm_automation_account.ops
  to   = module.automation.azurerm_automation_account.ops
}
moved {
  from = azurerm_role_assignment.automation_rg
  to   = module.automation.azurerm_role_assignment.automation_rg
}
moved {
  from = azurerm_automation_module.az_accounts
  to   = module.automation.azurerm_automation_module.az_accounts
}
moved {
  from = azurerm_automation_module.az_compute
  to   = module.automation.azurerm_automation_module.az_compute
}
moved {
  from = azurerm_automation_module.az_postgresql
  to   = module.automation.azurerm_automation_module.az_postgresql
}
moved {
  from = azurerm_automation_runbook.vm_start
  to   = module.automation.azurerm_automation_runbook.vm_start
}
moved {
  from = azurerm_automation_runbook.vm_stop
  to   = module.automation.azurerm_automation_runbook.vm_stop
}
moved {
  from = azurerm_automation_runbook.db_backup
  to   = module.automation.azurerm_automation_runbook.db_backup
}
moved {
  from = azurerm_automation_runbook.vm_snapshot
  to   = module.automation.azurerm_automation_runbook.vm_snapshot
}
moved {
  from = azurerm_automation_runbook.vm_snapshot_cleanup
  to   = module.automation.azurerm_automation_runbook.vm_snapshot_cleanup
}
moved {
  from = azurerm_automation_schedule.vm_start
  to   = module.automation.azurerm_automation_schedule.vm_start
}
moved {
  from = azurerm_automation_schedule.vm_stop
  to   = module.automation.azurerm_automation_schedule.vm_stop
}
moved {
  from = azurerm_automation_schedule.db_backup
  to   = module.automation.azurerm_automation_schedule.db_backup
}
moved {
  from = azurerm_automation_schedule.vm_snapshot_cleanup
  to   = module.automation.azurerm_automation_schedule.vm_snapshot_cleanup
}
moved {
  from = azurerm_automation_job_schedule.vm_start
  to   = module.automation.azurerm_automation_job_schedule.vm_start
}
moved {
  from = azurerm_automation_job_schedule.vm_stop
  to   = module.automation.azurerm_automation_job_schedule.vm_stop
}
moved {
  from = azurerm_automation_job_schedule.db_backup
  to   = module.automation.azurerm_automation_job_schedule.db_backup
}
moved {
  from = azurerm_automation_job_schedule.vm_snapshot_cleanup
  to   = module.automation.azurerm_automation_job_schedule.vm_snapshot_cleanup
}

# --- storage ---
moved {
  from = random_string.blob_suffix
  to   = module.storage.random_string.blob_suffix
}
moved {
  from = azurerm_storage_account.blob
  to   = module.storage.azurerm_storage_account.blob
}
