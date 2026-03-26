variable "resource_group_name" {
  description = "The name of the resource group in which the resources will be created"
  type        = string
  default     = "terraform-compute"
}

variable "environment" {
  description = "Logical environment name used for tags and generated inventory output paths."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "uat", "prod"], lower(var.environment))
    error_message = "The environment value must be one of: dev, uat, prod."
  }
}

variable "location" {
  description = "The location/region where the virtual network is created. Changing this forces a new resource to be created."
  type        = string
}

variable "vnet_address_space" {
  description = "The address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_address_prefix" {
  description = "The address prefix for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_ip_dns" {
  description = "Optional globally unique per datacenter region domain name label to apply to each public ip address. e.g. thisvar.varlocation.cloudapp.azure.com where you specify only thisvar here. This is an array of names which will pair up sequentially to the number of public ips defined in var.nb_public_ip. One name or empty string is required for every public ip. If no public ip is desired, then set this to an array with a single empty string."
  type        = list(string)
  default     = [""]
}

variable "admin_password" {
  description = "The admin password to be used on the VMSS that will be deployed. The password must meet the complexity requirements of Azure"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_key" {
  description = "Path to the public key to be used for ssh access to the VM."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ansible_inventory_file" {
  description = "Optional output path for the generated Ansible inventory file. Leave null to write to ansible/inventories/<environment>/hosts.ini."
  type        = string
  default     = null
}

variable "admin_username" {
  description = "The admin username of the VM that will be deployed"
  type        = string
  default     = "azureuser"
}

variable "storage_account_type" {
  description = "Defines the type of storage account to be created. Valid options are Standard_LRS, Standard_ZRS, Standard_GRS, Standard_RAGRS, Premium_LRS."
  type        = string
  default     = "Premium_LRS"
}

variable "vm_size" {
  description = "Specifies the size of the virtual machine."
  type        = string
  default     = "Standard_DS1_V2"
}

variable "nb_instances" {
  description = "Specify the number of vm instances"
  type        = number
  default     = 1
}

variable "vm_hostname" {
  description = "Prefix used for supporting Azure resources such as subnets, Bastion, and network security groups."
  type        = string
  default     = "myvm"
}

variable "private_vm_name" {
  description = "Name to assign to the private VM resource. When multiple private VMs are created, a numeric suffix is appended."
  type        = string
  default     = "privateVM"
}

variable "public_web_vm_name" {
  description = "Name to assign to the public web VM resource."
  type        = string
  default     = "publicWebapp"
}

variable "vm_os_simple" {
  description = "Specify UbuntuServer, WindowsServer, RHEL, openSUSE-Leap, CentOS, Debian, CoreOS and SLES to get the latest image version of the specified os. Do not provide this value if a custom value is used for vm_os_publisher, vm_os_offer, and vm_os_sku."
  type        = string
  default     = ""
}

variable "vm_os_id" {
  description = "The resource ID of the image that you want to deploy if you are using a custom image. Note, need to provide is_windows_image = true for windows custom images."
  type        = string
  default     = ""
}

variable "is_windows_image" {
  description = "Boolean flag to notify when the custom image is windows based. Only used in conjunction with vm_os_id"
  type        = bool
  default     = false
}

variable "vm_os_publisher" {
  description = "The name of the publisher of the image that you want to deploy. This is ignored when vm_os_id or vm_os_simple are provided."
  type        = string
  default     = ""
}

variable "vm_os_offer" {
  description = "The name of the offer of the image that you want to deploy. This is ignored when vm_os_id or vm_os_simple are provided."
  type        = string
  default     = ""
}

variable "vm_os_sku" {
  description = "The sku of the image that you want to deploy. This is ignored when vm_os_id or vm_os_simple are provided."
  type        = string
  default     = ""
}

variable "vm_os_version" {
  description = "The version of the image that you want to deploy. This is ignored when vm_os_id or vm_os_simple are provided."
  type        = string
  default     = "latest"
}

variable "tags" {
  type        = map(string)
  description = "A map of the tags to use on the resources that are deployed with this module."
  default = {
    source = "terraform"
  }
}

variable "public_ip_allocation_method" {
  description = "Defines how an IP address is assigned. Options are Static or Dynamic."
  type        = string
  default     = "Static"
}

variable "public_ip_sku" {
  description = "The SKU of the public IP. Options are Basic or Standard."
  type        = string
  default     = "Standard"
}

variable "nb_public_ip" {
  description = "Number of public IPs to assign corresponding to one IP per vm. Set to 0 to not assign any public IP addresses."
  type        = number
  default     = 1
}

variable "delete_os_disk_on_termination" {
  description = "Delete OS disk when machine is terminated (legacy variable, not used in azurerm 3.x)"
  type        = bool
  default     = false
}

variable "data_sa_type" {
  description = "Data Disk Storage Account type"
  type        = string
  default     = "Standard_LRS"
}

variable "data_disk_size_gb" {
  description = "Storage data disk size in GB"
  type        = number
  default     = 30
}

variable "data_disk" {
  description = "Set to true to add a datadisk."
  type        = bool
  default     = false
}

variable "admin_source_ip" {
  description = "Optional source IP or CIDR allowed to SSH to the public web VM. Leave null or empty to auto-detect your current public IP. Use '*' to allow from anywhere (not recommended)."
  type        = string
  default     = null
}

variable "enable_public_web_vm" {
  description = "Enable a public-facing Linux VM with a web server (nginx) installed via cloud-init."
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Enable a NAT Gateway for outbound internet access from private VMs without exposing them inbound."
  type        = bool
  default     = false
}

variable "enable_bastion" {
  description = "Enable Azure Bastion host as a jumpbox for private VM access."
  type        = bool
  default     = false
}

variable "bastion_subnet_address_prefix" {
  description = "The address prefix for the AzureBastionSubnet. Must be at least /26."
  type        = string
  default     = "10.0.2.0/26"
}

variable "boot_diagnostics" {
  description = "(Optional) Enable or Disable boot diagnostics"
  type        = bool
  default     = false
}

variable "boot_diagnostics_sa_type" {
  description = "(Optional) Storage account type for boot diagnostics"
  type        = string
  default     = "Standard_LRS"
}
