# Production environment
environment          = "prod"
location             = "eastus"
resource_group_name  = "terraform-compute-prod"
vm_hostname          = "myvmprod"
private_vm_name      = "privateVM"
public_web_vm_name   = "publicWebapp"
vm_os_simple         = "UbuntuServer"
vm_size              = "Standard_D4s_v3"
nb_instances         = 2
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
  lifecycle = "production"
}
