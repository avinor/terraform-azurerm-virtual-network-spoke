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

variable "log_analytics_workspace_id" {
  description = "Specifies the ID of a Log Analytics Workspace where Diagnostics Data should be sent."
  default     = null
}

variable "hub_virtual_network_id" {
  description = "Id of the hub virtual network that spoke should peer against."
}

variable "subnets" {
  description = "Subnets to create and their configuration. All values are required, set empty to ignore."
  type        = list(object({ name = string, address_prefix = string, service_endpoints = list(string), security_rules = list(any), routes = list(object({ name = string, address_prefix = string, next_hop_type = string, next_hop_in_ip_address = string })) }))
}

variable "use_remote_gateway" {
  description = "Use remote gateway when peering hub to spoke."
  type        = bool
  default     = true
}

variable "netwatcher" {
  description = "Properties for creating network watcher. If set it will create Network Watcher resource using standard naming standard."
  type        = object({ resource_group_location = string })
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources created."
  type        = map(string)
  default     = {}
}
