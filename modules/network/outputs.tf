output "network_interface_id" {
  description = "ID of the VM network interface."
  value       = azurerm_network_interface.vm.id
}

output "network_security_group_id" {
  description = "ID of the VM network security group."
  value       = azurerm_network_security_group.vm.id
}

output "public_ip_id" {
  description = "ID of the VM public IP."
  value       = azurerm_public_ip.vm.id
}

output "public_ip_address" {
  description = "Allocated public IP address of the VM."
  value       = azurerm_public_ip.vm.ip_address
}

output "subnet_id" {
  description = "ID of the VM subnet."
  value       = azurerm_subnet.vm.id
}
