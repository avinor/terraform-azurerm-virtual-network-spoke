output "vnet_id" {
  value = "${azurerm_virtual_network.vnet.id}"
}

output "vnet_rg" {
  value = "${local.spoke_rg_name}"
}

output "vnet_name" {
  value = "${local.spoke_vnet_name}"
}

output "subnets" {
  value = "${merge(zipmap(local.aks_subnets, azurerm_subnet.aks.*.id),
      map("mongo", azurerm_subnet.mongo.id))}"
}
