module "spoke" {
  source = "../../"

  name                   = "spoke"
  resource_group_name    = "networking-spoke-rg"
  location               = "westeurope"
  address_space          = ["10.0.0.0/16"]
  firewall_ip            = "10.0.0.4"
  hub_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mygroup1/providers/Microsoft.Network/virtualNetworks/myvnet1"

  subnets = [
    {
      name                   = "subnet"
      address_prefix         = "10.0.0.0/24"
      service_endpoints      = []
      security_rules         = []
      disable_firewall_route = false
    },
    {
      name                   = "subnet_null"
      address_prefix         = "10.0.1.0/24"
      service_endpoints      = []
      security_rules         = []
      disable_firewall_route = null
    },
    {
      name                   = "nofirewall"
      address_prefix         = "10.0.2.0/24"
      service_endpoints      = []
      security_rules         = []
      disable_firewall_route = true
    },
  ]

  diagnostics = {
    destination   = "test"
    eventhub_name = "diagnostics",
    logs          = ["all"],
    metrics       = ["all"],
  }
}
