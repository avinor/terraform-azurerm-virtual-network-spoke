terraform {
  required_version = ">= 0.12.6"
}

provider "azurerm" {
  version         = "~> 2.38.0"
  alias           = "hub"
  subscription_id = local.hub_subscription_id
  features {}
}

provider "azurerm" {
  version = "~> 2.38.0"
  features {}
}

provider "null" {
  version = "~> 2.1"
}

provider "random" {
  version = "~> 2.3"
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

  flatten_nsg_rules = flatten([for subnet in var.subnets :
    [for ridx, r in subnet.security_rules : {
      subnet   = subnet.name
      priority = 100 + 100 * ridx
      rule     = merge(local.default_nsg_rule, r)
    }]
  ])
  nsg_rules_map = { for rule in local.flatten_nsg_rules : "${rule.subnet}.${rule.priority}" => rule }

  subnets_with_routes = { for subnet in var.subnets : subnet.name => subnet if ! coalesce(subnet.disable_firewall_route, false) }
  subnets_map         = { for subnet in var.subnets : subnet.name => subnet }

  splitted_hub_vnet   = split("/", var.hub_virtual_network_id)
  hub_subscription_id = local.splitted_hub_vnet[2]
  hub_vnet_rg_name    = local.splitted_hub_vnet[4]
  hub_vnet_name       = local.splitted_hub_vnet[8]

  diag_vnet_logs = [
    "VMProtectionAlerts",
  ]
  diag_vnet_metrics = [
    "AllMetrics",
  ]
  diag_nsg_logs = [
    "NetworkSecurityGroupEvent",
    "NetworkSecurityGroupRuleCounter",
  ]

  diag_all_logs = setunion(
    local.diag_vnet_logs,
  local.diag_nsg_logs)
  diag_all_metrics = setunion(
  local.diag_vnet_metrics)

  diag_resource_list = var.diagnostics != null ? split("/", var.diagnostics.destination) : []
  parsed_diag = var.diagnostics != null ? {
    log_analytics_id   = contains(local.diag_resource_list, "Microsoft.OperationalInsights") ? var.diagnostics.destination : null
    storage_account_id = contains(local.diag_resource_list, "Microsoft.Storage") ? var.diagnostics.destination : null
    event_hub_auth_id  = contains(local.diag_resource_list, "Microsoft.EventHub") ? var.diagnostics.destination : null
    metric             = contains(var.diagnostics.metrics, "all") ? local.diag_all_metrics : var.diagnostics.metrics
    log                = contains(var.diagnostics.logs, "all") ? local.diag_all_logs : var.diagnostics.logs
    } : {
    log_analytics_id   = null
    storage_account_id = null
    event_hub_auth_id  = null
    metric             = []
    log                = []
  }
}

#
# Network watcher
# Following Azure naming standard to not create twice
#

resource "azurerm_resource_group" "netwatcher" {
  count    = var.netwatcher != null ? 1 : 0
  name     = "NetworkWatcherRG"
  location = var.netwatcher.resource_group_location

  tags = var.tags
}

resource "azurerm_network_watcher" "netwatcher" {
  count               = var.netwatcher != null ? 1 : 0
  name                = "NetworkWatcher_${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.netwatcher.0.name

  tags = var.tags
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

  address_space = var.address_space

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "vnet" {
  count                          = var.diagnostics != null ? 1 : 0
  name                           = "vnet-diag"
  target_resource_id             = azurerm_virtual_network.vnet.id
  log_analytics_workspace_id     = local.parsed_diag.log_analytics_id
  eventhub_authorization_rule_id = local.parsed_diag.event_hub_auth_id
  eventhub_name                  = local.parsed_diag.event_hub_auth_id != null ? var.diagnostics.eventhub_name : null
  storage_account_id             = local.parsed_diag.storage_account_id

  dynamic "log" {
    for_each = setintersection(local.parsed_diag.log, local.diag_vnet_logs)
    content {
      category = log.value

      retention_policy {
        enabled = false
      }
    }
  }

  dynamic "metric" {
    for_each = setintersection(local.parsed_diag.metric, local.diag_vnet_metrics)
    content {
      category = metric.value

      retention_policy {
        enabled = false
      }
    }
  }
}

#
# Spoke subnets
#

resource "azurerm_subnet" "vnet" {
  for_each = local.subnets_map

  name                 = each.key
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value.address_prefix]

  service_endpoints = each.value.service_endpoints

  # TODO Add support for delegation. Some delegation doesnt support UDR

}

#
# Storage account for flow logs
#

module "storage" {
  source  = "avinor/storage-account/azurerm"
  version = "2.3.0"

  name                = var.name
  resource_group_name = azurerm_resource_group.vnet.name
  location            = azurerm_resource_group.vnet.location

  enable_advanced_threat_protection = true

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

resource "azurerm_route_table" "vnet" {
  name                = "${var.name}-outbound-rt"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags
}

resource "azurerm_route" "vnet" {
  name                   = "firewall"
  resource_group_name    = azurerm_resource_group.vnet.name
  route_table_name       = azurerm_route_table.vnet.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_ip
}

resource "azurerm_subnet_route_table_association" "vnet" {
  for_each = local.subnets_with_routes

  subnet_id      = azurerm_subnet.vnet[each.key].id
  route_table_id = azurerm_route_table.vnet.id
}

#
# Network Security Groups
#

resource "azurerm_network_security_group" "vnet" {
  for_each = local.subnets_map

  name                = "${each.key}-nsg"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags
}

resource "azurerm_network_watcher_flow_log" "vnet_logs" {
  for_each = var.netwatcher != null ? local.subnets_map : {}

  resource_group_name       = azurerm_resource_group.vnet.name
  enabled                   = true
  version                   = 2
  network_security_group_id = azurerm_network_security_group.vnet[each.key].id
  network_watcher_name      = azurerm_network_security_group.vnet[each.key].name
  storage_account_id        = module.storage.id

  traffic_analytics {
    enabled               = true
    workspace_id          = var.netwatcher.log_analytics_workspace_id
    workspace_region      = azurerm_resource_group.netwatcher[0].location
    workspace_resource_id = var.netwatcher.log_analytics_resource_id
  }

  retention_policy {
    days    = 0
    enabled = false
  }
}

//resource "null_resource" "vnet_logs" {
//  for_each = var.netwatcher != null ? local.subnets_map : {}
//
//  # TODO Use new resource when exists
//  provisioner "local-exec" {
//    command = "az network watcher flow-log configure
//-g ${azurerm_resource_group.vnet.name}
//--enabled true
//--log-version 2
//--nsg ${azurerm_network_security_group.vnet[each.key].name}
//--storage-account ${module.storage.id}
//--traffic-analytics true
//--workspace ${var.netwatcher.log_analytics_workspace_id}
//--subscription ${data.azurerm_client_config.current.subscription_id}"
//  }
//
//  depends_on = [azurerm_network_security_group.vnet]
//}

resource "azurerm_network_security_rule" "vnet" {
  for_each = local.nsg_rules_map

  resource_group_name         = azurerm_resource_group.vnet.name
  network_security_group_name = azurerm_network_security_group.vnet[each.value.subnet].name
  priority                    = each.value.priority

  name                                       = each.value.rule.name
  direction                                  = each.value.rule.direction
  access                                     = each.value.rule.access
  protocol                                   = each.value.rule.protocol
  description                                = each.value.rule.description
  source_port_range                          = each.value.rule.source_port_range
  source_port_ranges                         = each.value.rule.source_port_ranges
  destination_port_range                     = each.value.rule.destination_port_range
  destination_port_ranges                    = each.value.rule.destination_port_ranges
  source_address_prefix                      = each.value.rule.source_address_prefix
  source_address_prefixes                    = each.value.rule.source_address_prefixes
  source_application_security_group_ids      = each.value.rule.source_application_security_group_ids
  destination_address_prefix                 = each.value.rule.destination_address_prefix
  destination_address_prefixes               = each.value.rule.destination_address_prefixes
  destination_application_security_group_ids = each.value.rule.destination_application_security_group_ids
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each = local.subnets_map

  name                           = "${each.key}-diag"
  target_resource_id             = azurerm_network_security_group.vnet[each.key].id
  log_analytics_workspace_id     = local.parsed_diag.log_analytics_id
  eventhub_authorization_rule_id = local.parsed_diag.event_hub_auth_id
  eventhub_name                  = local.parsed_diag.event_hub_auth_id != null ? var.diagnostics.eventhub_name : null
  storage_account_id             = local.parsed_diag.storage_account_id

  dynamic "log" {
    for_each = setintersection(local.parsed_diag.log, local.diag_nsg_logs)
    content {
      category = log.value

      retention_policy {
        enabled = false
      }
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "vnet" {
  for_each = local.subnets_map

  subnet_id                 = azurerm_subnet.vnet[each.key].id
  network_security_group_id = azurerm_network_security_group.vnet[each.key].id
}

#
# Private DNS link
#

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  provider              = azurerm.hub
  count                 = var.private_dns_link != null ? 1 : 0
  name                  = "${var.name}-link-${random_string.hub.result}"
  resource_group_name   = var.private_dns_link.resource_group_name
  private_dns_zone_name = var.private_dns_link.zone_name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = true

  tags = var.tags
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

  depends_on = [azurerm_virtual_network.vnet]
}

resource "random_string" "hub" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_virtual_network_peering" "hub-to-spoke" {
  provider                     = azurerm.hub
  name                         = "peering-to-spoke-${var.name}-${random_string.hub.result}"
  resource_group_name          = local.hub_vnet_rg_name
  virtual_network_name         = local.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_peering.spoke-to-hub]
}
