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
      delegations = [
        {
          name = "fs"
          service_delegation = {
            name = "Microsoft.DBforPostgreSQL/flexibleServers"
            actions = [
              "Microsoft.Network/virtualNetworks/subnets/join/action",
            ]
          }
        },
      ]
    },
  ]
}
