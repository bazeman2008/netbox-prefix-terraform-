variable "netbox_url" {
  description = "NetBox server URL"
  type        = string
}

variable "netbox_api_token" {
  description = "NetBox API token"
  type        = string
  sensitive   = true
}

variable "prefixes" {
  description = "Map of prefixes to create in NetBox"
  type = map(object({
    prefix      = string
    description = optional(string)
    status      = optional(string, "active")
    is_pool     = optional(bool, false)
    vrf_id      = optional(number)
    site_id     = optional(number)
    tenant_id   = optional(number)
    role_id     = optional(number)
    tags        = optional(list(string), [])
  }))
  default = {}
}