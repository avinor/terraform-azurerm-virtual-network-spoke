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
}

variable "common_subscription_id" {
  description = "Subscription id of common account."
}

variable "common_access_key" {
  description = "Access key to common storage account."
}

variable "use_remote_gateway" {
  description = "Use remote gateway when peering hub to spoke."
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources created."
  type        = "map"
  default     = {}
}
