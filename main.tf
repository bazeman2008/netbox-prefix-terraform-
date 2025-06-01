terraform {
  required_providers {
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 3.0"
    }
  }
}

provider "netbox" {
  server_url = var.netbox_url
  api_token  = var.netbox_api_token
}

resource "netbox_prefix" "prefixes" {
  for_each = var.prefixes

  prefix      = each.value.prefix
  description = each.value.description
  status      = each.value.status
  tenant_id   = each.value.tenant_id
}