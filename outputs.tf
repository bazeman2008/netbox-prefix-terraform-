output "prefix_ids" {
  description = "Map of prefix names to their NetBox IDs"
  value = {
    for k, v in netbox_prefix.prefixes : k => v.id
  }
}

output "prefix_details" {
  description = "Complete details of created prefixes"
  value = {
    for k, v in netbox_prefix.prefixes : k => {
      id          = v.id
      prefix      = v.prefix
      description = v.description
      status      = v.status
      is_pool     = v.is_pool
      vrf_id      = v.vrf_id
      site_id     = v.site_id
      tenant_id   = v.tenant_id
      role_id     = v.role_id
      tags        = v.tags
    }
  }
}