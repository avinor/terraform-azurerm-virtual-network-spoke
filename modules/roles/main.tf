terraform {
  required_version = ">= 0.12.0"
  required_providers {
    azurerm = ">= 1.32.0"
  }
}

provider "azurerm" {
  subscription_id = local.hub_subscription_id
}

locals {
    splitted_hub_vnet   = split("/", var.hub_vnet_id)
  hub_subscription_id = local.splitted_hub_vnet[2]
}

resource "azurerm_role_definition" "peering" {
  name               = "virtual-network-peering-role"
  scope              = var.hub_vnet_id
  description = "Grant access to peer virtual network"

  permissions {
    actions     = [
        "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write",
        "Microsoft.Network/virtualNetworks/peer/action",
        "Microsoft.ClassicNetwork/virtualNetworks/peer/action",
        "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/read",
        "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [
    var.principal_id,
  ]
}

resource "azurerm_role_assignment" "peering" {
  scope              = var.hub_vnet_id
  role_definition_id = azurerm_role_definition.peering.id
  principal_id       = var.principal_id
}