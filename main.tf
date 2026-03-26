terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "os" {
  source       = "./os"
  vm_os_simple = var.vm_os_simple
}

resource "azurerm_resource_group" "vm" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.effective_tags
}

resource "azurerm_virtual_network" "vm" {
  name                = "cloudforce-vnet"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.vm.location
  resource_group_name = azurerm_resource_group.vm.name
  tags                = local.effective_tags
}

resource "azurerm_subnet" "vm" {
  name                 = "${var.vm_hostname}-subnet"
  resource_group_name  = azurerm_resource_group.vm.name
  virtual_network_name = azurerm_virtual_network.vm.name
  address_prefixes     = [var.subnet_address_prefix]
}

# --- NAT Gateway (outbound internet for private VMs) ---

resource "azurerm_public_ip" "nat" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "${var.vm_hostname}-nat-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.vm.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.effective_tags
}

resource "azurerm_nat_gateway" "vm" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "${var.vm_hostname}-natgw"
  location            = var.location
  resource_group_name = azurerm_resource_group.vm.name
  sku_name            = "Standard"
  tags                = local.effective_tags
}

resource "azurerm_nat_gateway_public_ip_association" "vm" {
  count                = var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.vm[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "vm" {
  count          = var.enable_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.vm.id
  nat_gateway_id = azurerm_nat_gateway.vm[0].id
}

resource "azurerm_subnet" "bastion" {
  count                = var.enable_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.vm.name
  virtual_network_name = azurerm_virtual_network.vm.name
  address_prefixes     = [var.bastion_subnet_address_prefix]
}

resource "azurerm_network_security_group" "vm" {
  name                = "${var.vm_hostname}-nsg"
  location            = azurerm_resource_group.vm.location
  resource_group_name = azurerm_resource_group.vm.name
  tags                = local.effective_tags

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.enable_bastion ? var.vnet_address_space : "*"
    destination_address_prefix = "*"
  }
}

resource "random_id" "vm-sa" {
  keepers = {
    vm_hostname = var.vm_hostname
  }

  byte_length = 6
}

resource "azurerm_storage_account" "vm-sa" {
  count                    = var.boot_diagnostics ? 1 : 0
  name                     = "bootdiag${lower(random_id.vm-sa.hex)}"
  resource_group_name      = azurerm_resource_group.vm.name
  location                 = var.location
  account_tier             = element(split("_", var.boot_diagnostics_sa_type), 0)
  account_replication_type = element(split("_", var.boot_diagnostics_sa_type), 1)
  tags                     = local.effective_tags
}

resource "azurerm_linux_virtual_machine" "vm-linux" {
  count                 = !contains([var.vm_os_simple, var.vm_os_offer], "WindowsServer") && !var.is_windows_image && !var.data_disk ? var.nb_instances : 0
  name                  = "${var.vm_hostname}${count.index}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.vm.name
  availability_set_id   = azurerm_availability_set.vm.id
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.vm[count.index].id]
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_key)
  }

  source_image_reference {
    publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os.calculated_value_os_publisher) : ""
    offer     = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os.calculated_value_os_offer) : ""
    sku       = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os.calculated_value_os_sku) : ""
    version   = var.vm_os_id == "" ? var.vm_os_version : ""
  }

  os_disk {
    name                 = "osdisk-${var.vm_hostname}-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
  }

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics ? [1] : []
    content {
      storage_account_uri = azurerm_storage_account.vm-sa[0].primary_blob_endpoint
    }
  }

  tags = local.effective_tags
}

resource "azurerm_linux_virtual_machine" "vm-linux-with-datadisk" {
  count                 = !contains([var.vm_os_simple, var.vm_os_offer], "WindowsServer") && !var.is_windows_image && var.data_disk ? var.nb_instances : 0
  name                  = "${var.vm_hostname}${count.index}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.vm.name
  availability_set_id   = azurerm_availability_set.vm.id
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.vm[count.index].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_key)
  }

  source_image_reference {
    publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os.calculated_value_os_publisher) : ""
    offer     = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os.calculated_value_os_offer) : ""
    sku       = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os.calculated_value_os_sku) : ""
    version   = var.vm_os_id == "" ? var.vm_os_version : ""
  }

  os_disk {
    name                 = "osdisk-${var.vm_hostname}-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
  }

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics ? [1] : []
    content {
      storage_account_uri = azurerm_storage_account.vm-sa[0].primary_blob_endpoint
    }
  }

  tags = local.effective_tags
}

resource "azurerm_managed_disk" "datadisk" {
  count                = !contains([var.vm_os_simple, var.vm_os_offer], "WindowsServer") && !var.is_windows_image && var.data_disk ? var.nb_instances : 0
  name                 = "datadisk-${var.vm_hostname}-${count.index}"
  location             = var.location
  resource_group_name  = azurerm_resource_group.vm.name
  storage_account_type = var.data_sa_type
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  tags                 = local.effective_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "datadisk" {
  count              = !contains([var.vm_os_simple, var.vm_os_offer], "WindowsServer") && !var.is_windows_image && var.data_disk ? var.nb_instances : 0
  managed_disk_id    = azurerm_managed_disk.datadisk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.vm-linux-with-datadisk[count.index].id
  lun                = 0
  caching            = "ReadWrite"
}

resource "azurerm_windows_virtual_machine" "vm-windows" {
  count                 = ((var.vm_os_id != "" && var.is_windows_image) || contains([var.vm_os_simple, var.vm_os_offer], "WindowsServer")) && !var.data_disk ? var.nb_instances : 0
  name                  = "${var.vm_hostname}${count.index}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.vm.name
  availability_set_id   = azurerm_availability_set.vm.id
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.vm[count.index].id]

  source_image_reference {
    publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os.calculated_value_os_publisher) : ""
    offer     = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os.calculated_value_os_offer) : ""
    sku       = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os.calculated_value_os_sku) : ""
    version   = var.vm_os_id == "" ? var.vm_os_version : ""
  }

  os_disk {
    name                 = "osdisk-${var.vm_hostname}-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
  }

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics ? [1] : []
    content {
      storage_account_uri = azurerm_storage_account.vm-sa[0].primary_blob_endpoint
    }
  }

  tags = local.effective_tags
}

resource "azurerm_windows_virtual_machine" "vm-windows-with-datadisk" {
  count                 = ((var.vm_os_id != "" && var.is_windows_image) || contains([var.vm_os_simple, var.vm_os_offer], "WindowsServer")) && var.data_disk ? var.nb_instances : 0
  name                  = "${var.vm_hostname}${count.index}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.vm.name
  availability_set_id   = azurerm_availability_set.vm.id
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.vm[count.index].id]

  source_image_reference {
    publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os.calculated_value_os_publisher) : ""
    offer     = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os.calculated_value_os_offer) : ""
    sku       = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os.calculated_value_os_sku) : ""
    version   = var.vm_os_id == "" ? var.vm_os_version : ""
  }

  os_disk {
    name                 = "osdisk-${var.vm_hostname}-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
  }

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics ? [1] : []
    content {
      storage_account_uri = azurerm_storage_account.vm-sa[0].primary_blob_endpoint
    }
  }

  tags = local.effective_tags
}

resource "azurerm_managed_disk" "windows-datadisk" {
  count                = ((var.vm_os_id != "" && var.is_windows_image) || contains([var.vm_os_simple, var.vm_os_offer], "WindowsServer")) && var.data_disk ? var.nb_instances : 0
  name                 = "datadisk-${var.vm_hostname}-${count.index}"
  location             = var.location
  resource_group_name  = azurerm_resource_group.vm.name
  storage_account_type = var.data_sa_type
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  tags                 = local.effective_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "windows-datadisk" {
  count              = ((var.vm_os_id != "" && var.is_windows_image) || contains([var.vm_os_simple, var.vm_os_offer], "WindowsServer")) && var.data_disk ? var.nb_instances : 0
  managed_disk_id    = azurerm_managed_disk.windows-datadisk[count.index].id
  virtual_machine_id = azurerm_windows_virtual_machine.vm-windows-with-datadisk[count.index].id
  lun                = 0
  caching            = "ReadWrite"
}

resource "azurerm_availability_set" "vm" {
  name                         = "${var.vm_hostname}-avset"
  location                     = azurerm_resource_group.vm.location
  resource_group_name          = azurerm_resource_group.vm.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
}

resource "azurerm_public_ip" "vm" {
  count               = var.nb_public_ip
  name                = "${var.vm_hostname}-${count.index}-publicIP"
  location            = var.location
  resource_group_name = azurerm_resource_group.vm.name
  allocation_method   = var.public_ip_allocation_method
  sku                 = var.public_ip_sku
  domain_name_label   = element(var.public_ip_dns, count.index) != "" ? element(var.public_ip_dns, count.index) : null
  tags                = local.effective_tags
}

resource "azurerm_network_interface" "vm" {
  count               = var.nb_instances
  name                = "nic-${var.vm_hostname}-${count.index}"
  location            = azurerm_resource_group.vm.location
  resource_group_name = azurerm_resource_group.vm.name

  ip_configuration {
    name                          = "ipconfig${count.index}"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = length(azurerm_public_ip.vm) > 0 ? element(concat(azurerm_public_ip.vm[*].id, [""]), count.index) : null
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  count                     = var.nb_instances
  network_interface_id      = azurerm_network_interface.vm[count.index].id
  network_security_group_id = azurerm_network_security_group.vm.id
}

# --- Azure Bastion ---

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "${var.vm_hostname}-bastion-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.vm.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.effective_tags
}

resource "azurerm_bastion_host" "vm" {
  count               = var.enable_bastion ? 1 : 0
  name                = "${var.vm_hostname}-bastion"
  location            = var.location
  resource_group_name = azurerm_resource_group.vm.name
  sku                 = "Standard"
  tunneling_enabled   = true

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = local.effective_tags
}

# --- Public Web VM ---

resource "azurerm_network_security_group" "web" {
  count               = var.enable_public_web_vm ? 1 : 0
  name                = "${var.vm_hostname}-web-nsg"
  location            = azurerm_resource_group.vm.location
  resource_group_name = azurerm_resource_group.vm.name
  tags                = local.effective_tags

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
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
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_source_ip
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "web" {
  count               = var.enable_public_web_vm ? 1 : 0
  name                = "${var.vm_hostname}-web-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.vm.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.effective_tags
}

resource "azurerm_network_interface" "web" {
  count               = var.enable_public_web_vm ? 1 : 0
  name                = "nic-${var.vm_hostname}-web"
  location            = azurerm_resource_group.vm.location
  resource_group_name = azurerm_resource_group.vm.name

  ip_configuration {
    name                          = "ipconfig-web"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web[0].id
  }
}

resource "azurerm_network_interface_security_group_association" "web" {
  count                     = var.enable_public_web_vm ? 1 : 0
  network_interface_id      = azurerm_network_interface.web[0].id
  network_security_group_id = azurerm_network_security_group.web[0].id
}

resource "azurerm_linux_virtual_machine" "web" {
  count                 = var.enable_public_web_vm ? 1 : 0
  name                  = "${var.vm_hostname}-web"
  location              = var.location
  resource_group_name   = azurerm_resource_group.vm.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.web[0].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_key)
  }

  source_image_reference {
    publisher = coalesce(var.vm_os_publisher, module.os.calculated_value_os_publisher)
    offer     = coalesce(var.vm_os_offer, module.os.calculated_value_os_offer)
    sku       = coalesce(var.vm_os_sku, module.os.calculated_value_os_sku)
    version   = var.vm_os_version
  }

  os_disk {
    name                 = "osdisk-${var.vm_hostname}-web"
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
  }

  tags = local.effective_tags
}

# Generate Ansible inventory from Terraform state
resource "local_file" "ansible_inventory" {
  filename = local.ansible_inventory_output_path
  content = templatefile("${path.module}/ansible/inventory.tpl", {
    web_vm_public_ip    = var.enable_public_web_vm ? azurerm_public_ip.web[0].ip_address : ""
    private_vm_ips      = azurerm_network_interface.vm[*].private_ip_address
    admin_username      = var.admin_username
    ssh_key_path        = var.ssh_key
    bastion_name        = var.enable_bastion ? azurerm_bastion_host.vm[0].name : ""
    resource_group_name = azurerm_resource_group.vm.name
    enable_bastion      = var.enable_bastion
    enable_web_vm       = var.enable_public_web_vm
  })
}
