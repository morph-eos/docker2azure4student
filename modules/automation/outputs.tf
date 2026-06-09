output "automation_account_id" {
  description = "ID of the Automation account (null when no automation feature is enabled)."
  value       = local.automation_required ? azurerm_automation_account.ops[0].id : null
}

output "automation_account_name" {
  description = "Name of the Automation account (null when no automation feature is enabled)."
  value       = local.automation_required ? azurerm_automation_account.ops[0].name : null
}
