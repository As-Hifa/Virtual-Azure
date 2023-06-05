terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "sido-pro" {
  name     = "sido-pro"
  location = "eastus"
  
}

resource "azurerm_network_security_group" "vm-nsg" {
  name                = "vm-nsg"
  location            = azurerm_resource_group.sido-pro.location
  resource_group_name = azurerm_resource_group.sido-pro.name



  security_rule {
    name                       = "inbound1"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }


  security_rule {
    name                       = "Outbound"
    priority                   = 300
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "nsg-for-vm" {
  subnet_id                 = azurerm_subnet.vm-subnet.id
  network_security_group_id = azurerm_network_security_group.vm-nsg.id
}

resource "azurerm_virtual_network" "vnet-1" {
  name                = "vnet-1"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.sido-pro.location
  resource_group_name = azurerm_resource_group.sido-pro.name
  tags = {con="conn"}
}

resource "azurerm_subnet" "vm-subnet" {
  name                 = "vm-subnet"
  resource_group_name  = azurerm_resource_group.sido-pro.name
  virtual_network_name = azurerm_virtual_network.vnet-1.name
  address_prefixes     = ["10.0.1.0/24"]
}


resource "azurerm_subnet" "sql-subnet" {
  name                 = "sql-subnet"
  resource_group_name  = azurerm_resource_group.sido-pro.name
  virtual_network_name = azurerm_virtual_network.vnet-1.name
  address_prefixes     = ["10.0.2.0/24"]
  enforce_private_link_service_network_policies = true
  service_endpoints    = ["Microsoft.Storage"]
    delegation {
    name = "fs"

    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_network_security_group" "sql-nsg" {
  name                = "sql-nsg"
  location            = azurerm_resource_group.sido-pro.location
  resource_group_name = azurerm_resource_group.sido-pro.name

  security_rule {
    name                       = "inbound1"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg-for-sql" {
  subnet_id                 = azurerm_subnet.sql-subnet.id
  network_security_group_id = azurerm_network_security_group.sql-nsg.id
}

resource "azurerm_network_interface" "pro-nic" {
  count               = 3
  name                = "pro-nic${count.index}"
  location            = azurerm_resource_group.sido-pro.location
  resource_group_name = azurerm_resource_group.sido-pro.name
  tags = {con="conn"}
  
  
  ip_configuration {
    name                          = "internal${count.index}"
    subnet_id                     = azurerm_subnet.vm-subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "severs" {
  count                 = 3
  name                  = "vm-${count.index}"
  location              = azurerm_resource_group.sido-pro.location
  resource_group_name   = azurerm_resource_group.sido-pro.name
  size                  = "Standard_B1ls"
  admin_username        = "adminuser${count.index}"
  admin_password        = "As1234567890"
  disable_password_authentication = false
  tags = {con="conn"}
  network_interface_ids = [
    azurerm_network_interface.pro-nic[count.index].id
  ]
  availability_set_id = azurerm_availability_set.ava-set.id
  depends_on = [
    azurerm_subnet.vm-subnet,
    azurerm_network_interface.pro-nic,
    azurerm_availability_set.ava-set
  ]
  


  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

resource "azurerm_public_ip" "lb-ip" {
name                  = "Public_IP_For_LB"
location              = azurerm_resource_group.sido-pro.location
resource_group_name   = azurerm_resource_group.sido-pro.name
allocation_method     = "Static"
}

resource "azurerm_lb" "lb-pro" {
name                  = "LoadBalancer"
location              = azurerm_resource_group.sido-pro.location
resource_group_name   = azurerm_resource_group.sido-pro.name
tags = {con="conn"}
depends_on = [
  azurerm_linux_virtual_machine.severs
]

  frontend_ip_configuration {
    name                 = "Public_IP_For_LB"
    public_ip_address_id = azurerm_public_ip.lb-ip.id
  }
  
}

resource "azurerm_lb_backend_address_pool" "back_end_adr" {
  loadbalancer_id = azurerm_lb.lb-pro.id
  name            = "BackEndAddressPool"
}

resource "azurerm_network_interface_backend_address_pool_association" "con_to_nic" {
  count                   = 3
  network_interface_id    = azurerm_network_interface.pro-nic.*.id[count.index]
  ip_configuration_name   = azurerm_network_interface.pro-nic.*.ip_configuration.0.name[count.index]
  backend_address_pool_id = azurerm_lb_backend_address_pool.back_end_adr.id
  depends_on = [
    azurerm_lb.lb-pro,
    azurerm_network_interface.pro-nic
  ]
}

  
resource "azurerm_lb_probe" "lb_prub" {
    name                       = "tcp-probe"
    protocol                   = "Tcp"
    port                       = 80
    number_of_probes           = 2
    loadbalancer_id            = azurerm_lb.lb-pro.id
}

resource "azurerm_lb_rule" "only_to_server" {
    name                              = "http-rule"
    loadbalancer_id                   = azurerm_lb.lb-pro.id
    frontend_ip_configuration_name    = "Public_IP_For_LB"
    backend_address_pool_ids           = [azurerm_lb_backend_address_pool.back_end_adr.id]
    protocol                          = "Tcp"
    frontend_port                     = 80
    backend_port                      = 80
    probe_id                          = azurerm_lb_probe.lb_prub.id
  }

##the second vnet with peering.

resource "azurerm_virtual_network_peering" "vnet1-to-test" {
  name                      = "vnet1-to-test"
  resource_group_name       = azurerm_resource_group.sido-pro.name
  virtual_network_name      = azurerm_virtual_network.vnet-1.name
  remote_virtual_network_id = azurerm_virtual_network.vnet-2.id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network" "vnet-2" {
  name                = "vnet-2"
  address_space       = ["10.2.0.0/16"]
  location            = azurerm_resource_group.sido-pro.location
  resource_group_name = azurerm_resource_group.sido-pro.name
}

resource "azurerm_subnet" "test-subnet" {
  name                 = "test-subnet"
  resource_group_name  = azurerm_resource_group.sido-pro.name
  virtual_network_name = azurerm_virtual_network.vnet-2.name
  address_prefixes     = ["10.2.0.0/24"] 
}

resource "azurerm_network_interface" "nic-test" {
  name                 = "nic-test"
  location             = azurerm_resource_group.sido-pro.location
  resource_group_name  = azurerm_resource_group.sido-pro.name

  ip_configuration {
    name                          = "test-ip"
    subnet_id                     = azurerm_subnet.test-subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}


resource "azurerm_linux_virtual_machine" "test-vm" {
  name                = "test-vm"
  resource_group_name = azurerm_resource_group.sido-pro.name
  location            = azurerm_resource_group.sido-pro.location
  size                = "Standard_B1ls"
  admin_username      = "test-vm"
  admin_password      = "As1234567890"
  disable_password_authentication = false
  depends_on = [
    azurerm_subnet.test-subnet
  ]
  network_interface_ids = [
    azurerm_network_interface.nic-test.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

resource "azurerm_virtual_network_peering" "test-to-vnet1" {
  name                      = "test-to-vnet1"
  resource_group_name       = azurerm_resource_group.sido-pro.name
  virtual_network_name      = azurerm_virtual_network.vnet-2.name
  remote_virtual_network_id = azurerm_virtual_network.vnet-1.id
  allow_forwarded_traffic   = true
}


resource "azurerm_availability_set" "ava-set" {
  name                = "ava-set"
  location            = azurerm_resource_group.sido-pro.location
  resource_group_name = azurerm_resource_group.sido-pro.name
  tags = {con="conn"}
  managed = true
}




