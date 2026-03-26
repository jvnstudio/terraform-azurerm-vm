# Development environment
environment          = "dev"
location             = "westus"
resource_group_name  = "terraform-compute-dev"
vm_hostname          = "myvmdev"
private_vm_name      = "privateVM"
public_web_vm_name   = "publicWebapp"
vm_os_simple         = "UbuntuServer"
vm_size              = "Standard_D2s_v3"
nb_instances         = 1
admin_username       = "azureuser"
ssh_key              = "~/.ssh/azure_rsa.pub"
nb_public_ip         = 0
public_ip_dns        = [""]
enable_bastion       = true
enable_public_web_vm = true
admin_source_ip      = "YOUR_PUBLIC_IP"
boot_diagnostics     = true

tags = {
  source    = "terraform"
  lifecycle = "development"
}
