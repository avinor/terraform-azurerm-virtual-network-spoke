provider "azurerm" {
  alias           = "hub"
  subscription_id = "${var.common_subscription_id}"
}

terraform {
  backend "azurerm" {}
}

data "azurerm_client_config" "current" {}

locals {
  spoke_rg_name   = "networking-spoke-${var.name}-${var.location}-rg"
  spoke_vnet_name = "${var.name}-spoke-vnet"
  aks_subnets     = ["aks_blue", "aks_green"]
}

#
# Spoke VNet
#

resource "azurerm_resource_group" "vnet" {
  name     = "${local.spoke_rg_name}"
  location = "${var.location}"

  tags = "${var.tags}"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.spoke_vnet_name}"
  location            = "${azurerm_resource_group.vnet.location}"
  resource_group_name = "${azurerm_resource_group.vnet.name}"

  address_space = ["${var.address_space}"]

  tags = "${var.tags}"
}

#
# Spoke subnets
#

resource "azurerm_subnet" "aks" {
  count                = "${length(local.aks_subnets)}"
  name                 = "${element(local.aks_subnets, count.index)}"
  resource_group_name  = "${azurerm_resource_group.vnet.name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  address_prefix       = "${cidrsubnet(var.address_space, 2, count.index)}"

  service_endpoints = [
    "Microsoft.Storage",
  ]

  lifecycle {
    # TODO Remove this when azurerm 2.0 provider is released
    ignore_changes = [
      "route_table_id",
      "network_security_group_id",
    ]
  }
}

resource "azurerm_subnet" "mongo" {
  name                 = "mongo"
  resource_group_name  = "${azurerm_resource_group.vnet.name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  address_prefix       = "${cidrsubnet(var.address_space, 6, 48)}"

  service_endpoints = [
    "Microsoft.Storage",
  ]

  lifecycle {
    # TODO Remove this when azurerm 2.0 provider is released
    ignore_changes = [
      "route_table_id",
      "network_security_group_id",
    ]
  }
}

# TODO Look at this later. delegated subnets do not support route tables
# resource "azurerm_subnet" "aci" {
#   name                 = "aci"
#   resource_group_name  = "${azurerm_resource_group.vnet.name}"
#   virtual_network_name = "${azurerm_virtual_network.vnet.name}"
#   address_prefix       = "${cidrsubnet(var.address_space, 6, 33)}"

#   delegation {
#     name = "aci-delegation"

#     service_delegation {
#       name    = "Microsoft.ContainerInstance/containerGroups"
#       actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
#     }
#   }

#   lifecycle {
#     # TODO Remove this when azurerm 2.0 provider is released
#     ignore_changes = [ "route_table_id" ]
#   }
# }

#
# Storage account for flow logs
#

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "network" {
  name                = "${format("spokenetwork%ssa", random_string.unique.result)}"
  resource_group_name = "${azurerm_resource_group.vnet.name}"

  location                  = "${azurerm_resource_group.vnet.location}"
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "ZRS"
  enable_https_traffic_only = true

  # TODO Not yet supported to use service endpoints together with flow logs. Not a trusted Microsoft service
  # See https://github.com/MicrosoftDocs/azure-docs/issues/5989
  # network_rules {
  #   ip_rules                   = ["127.0.0.1"]
  #   virtual_network_subnet_ids = ["${azurerm_subnet.firewall.id}"]
  # }

  tags = "${var.tags}"
}

#
# Route table
#

resource "azurerm_route_table" "public" {
  name                = "${var.name}-public-rt"
  location            = "${azurerm_resource_group.vnet.location}"
  resource_group_name = "${azurerm_resource_group.vnet.name}"

  tags = "${var.tags}"
}

resource "azurerm_route" "public_all" {
  name                   = "all"
  resource_group_name    = "${azurerm_resource_group.vnet.name}"
  route_table_name       = "${azurerm_route_table.public.name}"
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = "${data.terraform_remote_state.hub.firewall_private_ip}"
}

resource "azurerm_subnet_route_table_association" "aks" {
  count          = "${length(local.aks_subnets)}"
  subnet_id      = "${element(azurerm_subnet.aks.*.id, count.index)}"
  route_table_id = "${azurerm_route_table.public.id}"
}

resource "azurerm_subnet_route_table_association" "mongo" {
  subnet_id      = "${azurerm_subnet.mongo.id}"
  route_table_id = "${azurerm_route_table.public.id}"
}

# resource "azurerm_subnet_route_table_association" "aci" {
#   subnet_id      = "${azurerm_subnet.aci.id}"
#   route_table_id = "${azurerm_route_table.hub.id}"
# }

#
# Network Security Groups
#

resource "azurerm_network_security_group" "aks" {
  name                = "aks-nsg"
  location            = "${azurerm_resource_group.vnet.location}"
  resource_group_name = "${azurerm_resource_group.vnet.name}"

  security_rule {
    name                       = "allow-http-from-appgw"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "${data.azurerm_subnet.appgw.address_prefix}"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-ssh-from-mgmt"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${data.azurerm_subnet.mgmt.address_prefix}"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-load-balancer"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  tags = "${var.tags}"

  # TODO Does not exist as a resource...yet
  provisioner "local-exec" {
    command = "az network watcher flow-log configure -g ${azurerm_resource_group.vnet.name} --enabled true --log-version 2 --nsg aks-nsg --storage-account ${azurerm_storage_account.network.id} --traffic-analytics true --workspace ${data.terraform_remote_state.setup.log_resource_id} --subscription ${data.azurerm_client_config.current.subscription_id}"
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-log-analytics"
  target_resource_id         = "${azurerm_network_security_group.aks.id}"
  log_analytics_workspace_id = "${data.terraform_remote_state.setup.log_resource_id}"

  log {
    category = "NetworkSecurityGroupEvent"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "NetworkSecurityGroupRuleCounter"

    retention_policy {
      enabled = false
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  count                     = "${length(local.aks_subnets)}"
  subnet_id                 = "${element(azurerm_subnet.aks.*.id, count.index)}"
  network_security_group_id = "${azurerm_network_security_group.aks.id}"
}

resource "azurerm_network_security_group" "mongo" {
  name                = "mongo-nsg"
  location            = "${azurerm_resource_group.vnet.location}"
  resource_group_name = "${azurerm_resource_group.vnet.name}"

  security_rule {
    name                       = "allow-mongo-from-vnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "27017"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-ssh-from-mgmt"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${data.azurerm_subnet.mgmt.address_prefix}"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-load-balancer"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-vnet"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  tags = "${var.tags}"

  # TODO Does not exist as a resource...yet
  provisioner "local-exec" {
    command = "az network watcher flow-log configure -g ${azurerm_resource_group.vnet.name} --enabled true --log-version 2 --nsg mongo-nsg --storage-account ${azurerm_storage_account.network.id} --traffic-analytics true --workspace ${data.terraform_remote_state.setup.log_resource_id} --subscription ${data.azurerm_client_config.current.subscription_id}"
  }
}

resource "azurerm_monitor_diagnostic_setting" "mongo" {
  name                       = "mongo-log-analytics"
  target_resource_id         = "${azurerm_network_security_group.mongo.id}"
  log_analytics_workspace_id = "${data.terraform_remote_state.setup.log_resource_id}"

  log {
    category = "NetworkSecurityGroupEvent"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "NetworkSecurityGroupRuleCounter"

    retention_policy {
      enabled = false
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "mongo" {
  subnet_id                 = "${azurerm_subnet.mongo.id}"
  network_security_group_id = "${azurerm_network_security_group.mongo.id}"
}

#
# Peering
#

resource "azurerm_virtual_network_peering" "spoke-to-hub" {
  name                         = "peering-to-hub"
  resource_group_name          = "${azurerm_resource_group.vnet.name}"
  virtual_network_name         = "${local.spoke_vnet_name}"
  remote_virtual_network_id    = "${data.terraform_remote_state.hub.vnet_id}"
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = "${var.use_remote_gateway}"

  depends_on = ["azurerm_virtual_network.vnet"]
}

resource "azurerm_virtual_network_peering" "hub-to-spoke" {
  provider                     = "azurerm.hub"
  name                         = "peering-to-spoke-${var.name}"
  resource_group_name          = "${data.terraform_remote_state.hub.vnet_rg}"
  virtual_network_name         = "${data.terraform_remote_state.hub.vnet_name}"
  remote_virtual_network_id    = "${azurerm_virtual_network.vnet.id}"
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false

  depends_on = ["azurerm_virtual_network_peering.spoke-to-hub"]
}
