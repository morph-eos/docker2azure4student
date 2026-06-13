output "vm_id" {
  description = "ID of the Linux virtual machine."
  value       = azurerm_linux_virtual_machine.app.id
}

output "vm_name" {
  description = "Name of the Linux virtual machine."
  value       = azurerm_linux_virtual_machine.app.name
}

output "vm_principal_id" {
  description = "Principal ID of the VM system-assigned managed identity."
  value       = azurerm_linux_virtual_machine.app.identity[0].principal_id
}
