output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "vnet_resource_group_name" {
  value = var.resource_group_name
}

output "vnet_name" {
  value = azurerm_virtual_network.vnet.name
}

output "subnets" {
  value = zipmap(var.subnets.*.name, azurerm_subnet.vnet.*.id)
}
