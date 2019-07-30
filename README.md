# Virtual network spoke

Terraform module to create a spoke virtual network according to Microsoft Best Practice of deploying Hub-Spoke architecture. This requires that the hub network has already been deployed and that the service principal have access, see [Setup](#setup) for more details.

## Recommendation

It is recommended to define as few service endpoints as possible on spoke subnets. Defining storage can be useful as it does not clutter the firewall log with all VM disk accesses, but besides that only define if absolutely necessary.

Firewall subnet has all service endpoints defined so traffic will still go to Azure Backbone, but routed through firewall so all traffic is logged.

## Limitations

Currently spoke subnets do not support delegation as not all delegation resources support UDR, for instance containers. Since all subnets have an UDR for routing traffic through the firewall in hub this is a requirement for spoke.

It is not an option to turn off UDR as that allows any subnet to create public ips and have full access out.

## Setup

Since spoke requires access to hub network to initiate peering it requires access to hub virtual network. Service principal that deploys spoke therefore needs a custom role, or Network Contributor role on hub virtual network. See [Microsoft documentation](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-manage-peering#permissions) for required setup.

If Log Analytics workspace is created in another subscription it is required that service principal has Log Analytics Contributor role on workspace, or a custom role allowing it to connect resources to workspace.

## Usage

Example below only creates a single subnet, but it can create as many as required. Each subnet has its own service endpoint and security rules (NSG) defined. There are no default security rules so if its required to have a deny_all rule make sure to add it last in the list.

Example uses [tau](https://github.com/avinor/tau).

```terraform
module {
    source = "avinor/virtual-network-spoke/azurerm"
    version = "1.0.0"
}

inputs {
    name = "spoke"
    resource_group_name = "networking-spoke-rg"
    location = "westeurope"
    address_space = "10.0.0.0/16"
    firewall_ip = "10.0.0.4"
    hub_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mygroup1/providers/Microsoft.Network/virtualNetworks/myvnet1"

    subnets = [
        {
            name = "subnet"
            address_prefix = "10.0.0.0/24"
            service_endpoints = []
            security_rules = []
        },
    ]
}
```

## Network watcher

If defining the input variable `netwatcher` it will create a Network Watcher resource. Since Azure uses a specific naming standard on network watchers it tries to conform to that. It will create a resource group NetworkWatcherRG in location specific in `netwatcher` input variable.

## Input

By default `use_remote_gateway` is set to true but this requires that the hub has a virtual gateway deployed. Set to false if there is no virtual gateway in hub network.

### subnets

| Variable          | Description
|-------------------|-------------
| name              | Name of the subnet
| address_prefix    | Address prefix for subnet
| service_endpoints | List of service endpoints to activate.
| security_rules    | Complex object that supports all properties of `azurerm_network_security_rule`. No need to define priority.
