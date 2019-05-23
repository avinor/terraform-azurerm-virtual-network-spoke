terraform {
  backend "azurerm" {}
  required_version = ">= 0.12.0"
  required_providers {
    azurerm = ">= 1.28.0"
  }
}

provider "azurerm" {
  alias           = "hub"
  subscription_id = local.hub_subscription_id
}

data "azurerm_client_config" "current" {}

locals {
  default_nsg_rule = {
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    description                                = null
    source_port_range                          = null
    source_port_ranges                         = null
    destination_port_range                     = null
    destination_port_ranges                    = null
    source_address_prefix                      = null
    source_address_prefixes                    = null
    source_application_security_group_ids      = null
    destination_address_prefix                 = null
    destination_address_prefixes               = null
    destination_application_security_group_ids = null
  }

  flatten_nsg_rules = flatten([for idx, subnet in var.subnets :
    [for ridx, r in subnet.security_rules : {
      subnet   = idx
      priority = 100 + 100 * ridx
      rule     = merge(local.default_nsg_rule, r)
    }]
  ])

  splitted_hub_vnet   = split("/", var.hub_virtual_network_id)
  hub_subscription_id = local.splitted_hub_vnet[2]
  hub_vnet_rg_name    = local.splitted_hub_vnet[4]
  hub_vnet_name       = local.splitted_hub_vnet[8]
}

#
# Spoke VNet
#

resource "azurerm_resource_group" "vnet" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.name}-vnet"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  address_space = [var.address_space]

  tags = var.tags
}

#
# Spoke subnets
#

resource "azurerm_subnet" "vnet" {
  count                = length(var.subnets)
  name                 = var.subnets[count.index].name
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix       = var.subnets[count.index].address_prefix

  service_endpoints = var.subnets[count.index].service_endpoints

  # TODO Add support for delegation. Some delegation doesnt support UDR

  lifecycle {
    # TODO Remove this when azurerm 2.0 provider is released
    ignore_changes = [
      "route_table_id",
      "network_security_group_id",
    ]
  }
}

#
# Storage account for flow logs
#

module "storage" {
  source  = "avinor/storage-account/azurerm"
  version = "1.0.0"

  name                = var.name
  resource_group_name = azurerm_resource_group.vnet.name
  location            = azurerm_resource_group.vnet.location

  # TODO Not yet supported to use service endpoints together with flow logs. Not a trusted Microsoft service
  # See https://github.com/MicrosoftDocs/azure-docs/issues/5989
  # network_rules {
  #   ip_rules                   = ["127.0.0.1"]
  #   virtual_network_subnet_ids = ["${azurerm_subnet.firewall.id}"]
  # }

  tags = var.tags
}

#
# Route table
#

resource "azurerm_route_table" "outbound" {
  name                = "${var.name}-outbound-rt"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags
}

resource "azurerm_route" "outbound" {
  name                   = "outbound"
  resource_group_name    = azurerm_resource_group.vnet.name
  route_table_name       = azurerm_route_table.outbound.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_ip
}

resource "azurerm_subnet_route_table_association" "aks" {
  count          = length(var.subnets)
  subnet_id      = azurerm_subnet.vnet[count.index].id
  route_table_id = azurerm_route_table.outbound.id
}

#
# Network Security Groups
#

resource "azurerm_network_security_group" "vnet" {
  count               = length(var.subnets)
  name                = "${var.subnets[count.index].name}-nsg"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags

  # TODO Does not exist as a resource...yet
  provisioner "local-exec" {
    command = "az network watcher flow-log configure -g ${azurerm_resource_group.vnet.name} --enabled true --log-version 2 --nsg ${var.subnets[count.index].name}-nsg --storage-account ${module.storage.id} --traffic-analytics true --workspace ${var.log_analytics_workspace_id} --subscription ${data.azurerm_client_config.current.subscription_id}"
  }
}

resource "azurerm_network_security_rule" "vnet" {
  count                       = length(local.flatten_nsg_rules)
  resource_group_name         = azurerm_resource_group.vnet.name
  network_security_group_name = azurerm_network_security_group.vnet[local.flatten_nsg_rules[count.index].subnet].name
  priority                    = local.flatten_nsg_rules[count.index].priority

  name                                       = local.flatten_nsg_rules[count.index].rule.name
  direction                                  = local.flatten_nsg_rules[count.index].rule.direction
  access                                     = local.flatten_nsg_rules[count.index].rule.access
  protocol                                   = local.flatten_nsg_rules[count.index].rule.protocol
  description                                = local.flatten_nsg_rules[count.index].rule.description
  source_port_range                          = local.flatten_nsg_rules[count.index].rule.source_port_range
  source_port_ranges                         = local.flatten_nsg_rules[count.index].rule.source_port_ranges
  destination_port_range                     = local.flatten_nsg_rules[count.index].rule.destination_port_range
  destination_port_ranges                    = local.flatten_nsg_rules[count.index].rule.destination_port_ranges
  source_address_prefix                      = local.flatten_nsg_rules[count.index].rule.source_address_prefix
  source_address_prefixes                    = local.flatten_nsg_rules[count.index].rule.source_address_prefixes
  source_application_security_group_ids      = local.flatten_nsg_rules[count.index].rule.source_application_security_group_ids
  destination_address_prefix                 = local.flatten_nsg_rules[count.index].rule.destination_address_prefix
  destination_address_prefixes               = local.flatten_nsg_rules[count.index].rule.destination_address_prefixes
  destination_application_security_group_ids = local.flatten_nsg_rules[count.index].rule.destination_application_security_group_ids
}

resource "azurerm_monitor_diagnostic_setting" "vnet" {
  count                      = var.log_analytics_workspace_id != null ? length(var.subnets) : 0
  name                       = "${var.subnets[count.index].name}-log-analytics"
  target_resource_id         = azurerm_network_security_group.vnet[count.index].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

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

resource "azurerm_subnet_network_security_group_association" "vnet" {
  count                     = length(var.subnets)
  subnet_id                 = azurerm_subnet.vnet[count.index].id
  network_security_group_id = azurerm_network_security_group.vnet[count.index].id
}

#
# Peering
#

resource "azurerm_virtual_network_peering" "spoke-to-hub" {
  name                         = "peering-to-hub"
  resource_group_name          = azurerm_resource_group.vnet.name
  virtual_network_name         = azurerm_virtual_network.vnet.name
  remote_virtual_network_id    = var.hub_virtual_network_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.use_remote_gateway

  depends_on = ["azurerm_virtual_network.vnet"]
}

resource "azurerm_virtual_network_peering" "hub-to-spoke" {
  provider                     = "azurerm.hub"
  name                         = "peering-to-spoke-${var.name}"
  resource_group_name          = local.hub_vnet_rg_name
  virtual_network_name         = local.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false

  depends_on = ["azurerm_virtual_network_peering.spoke-to-hub"]
}
