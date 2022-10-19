variable "enable_advanced_threat_protection" {
  description = "Boolean flag which controls if advanced threat protection is enabled."
  type        = bool
  default     = true
}

variable "name" {
  description = "Name of the spoke virtual network."
}

variable "resource_group_name" {
  description = "Name of resource group to deploy resources in."
}

variable "location" {
  description = "The Azure Region in which to create resource."
}

variable "address_space" {
  description = "The address space that is used the virtual network."
  type        = list(string)
}

variable "diagnostics" {
  description = "Diagnostic settings for those resources that support it. See README.md for details on configuration."
  type = object({
    destination   = string
    eventhub_name = optional(string)
    logs          = list(string)
    metrics       = list(string)
  })
  default = null
}

variable "hub_virtual_network_id" {
  description = "Id of the hub virtual network that spoke should peer against."
}

variable "firewall_ip" {
  description = "Private ip of firewall to route all traffic through."
}

variable "subnets" {
  description = "Subnets to create and their configuration. All values are required, set empty to ignore."
  type = list(object({
    name                   = string
    address_prefix         = string
    service_endpoints      = optional(list(string), [])
    security_rules         = optional(list(any), [])
    disable_firewall_route = bool
    delegations = optional(list(object({
      name = string
      service_delegation = object({
        name    = string
        actions = list(string)
      })
    })), [])
  }))
}

variable "use_remote_gateway" {
  description = "Use remote gateway when peering hub to spoke."
  type        = bool
  default     = true
}

variable "private_dns_link" {
  description = "Private dns link with auto-registration enabled"
  type = object({
    resource_group_name = string
    zone_name           = string
  })
  default = null
}

variable "resolvable_dns_links" {
  description = "Private dns links with auto-registration disabled"
  type        = list(string)
  default     = []
}

variable "netwatcher" {
  description = "Properties for creating network watcher. If set it will create Network Watcher resource using standard naming standard."
  type = object({
    resource_group_location    = string
    log_analytics_workspace_id = string
    log_analytics_resource_id  = string
  })
  default = null
}

variable "storage_account_resource_group_create" {
  description = "Property for supporting terraform state created by older version of this module. NEVER set this to true for new spokes!"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources created."
  type        = map(string)
  default     = {}
}
