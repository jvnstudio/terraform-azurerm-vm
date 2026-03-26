output "vm_ids" {
  description = "Virtual machine ids created."
  value       = concat(azurerm_linux_virtual_machine.vm-linux[*].id, azurerm_linux_virtual_machine.vm-linux-with-datadisk[*].id, azurerm_windows_virtual_machine.vm-windows[*].id, azurerm_windows_virtual_machine.vm-windows-with-datadisk[*].id)
}

output "network_interface_ids" {
  description = "ids of the vm nics provisioned."
  value       = azurerm_network_interface.vm[*].id
}

output "network_interface_private_ip" {
  description = "private ip addresses of the vm nics"
  value       = azurerm_network_interface.vm[*].private_ip_address
}

output "availability_set_id" {
  description = "id of the availability set where the vms are provisioned."
  value       = azurerm_availability_set.vm.id
}

output "public_ip_id" {
  description = "id of the public ip address provisioned."
  value       = azurerm_public_ip.vm[*].id
}

output "public_ip_address" {
  description = "The actual ip address allocated for the resource."
  value       = azurerm_public_ip.vm[*].ip_address
}

output "public_ip_dns_name" {
  description = "fqdn to connect to the first vm provisioned."
  value       = azurerm_public_ip.vm[*].fqdn
}

output "web_vm_public_ip" {
  description = "The public IP address of the web VM."
  value       = var.enable_public_web_vm ? azurerm_public_ip.web[0].ip_address : null
}

output "web_vm_url" {
  description = "The URL to access the web app."
  value       = var.enable_public_web_vm ? "http://${azurerm_public_ip.web[0].ip_address}" : null
}

output "bastion_name" {
  description = "The name of the Azure Bastion host."
  value       = var.enable_bastion ? azurerm_bastion_host.vm[0].name : null
}

output "bastion_dns_name" {
  description = "The FQDN of the Azure Bastion host."
  value       = var.enable_bastion ? azurerm_bastion_host.vm[0].dns_name : null
}
