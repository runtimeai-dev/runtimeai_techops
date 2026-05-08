# OPER_RT19-084p — Azure Front Door for mcp.runtimeai.io
# Sticky-by-tenant routing across rt19 / rt01 / rt02 with health-probe
# auto-failover. The tenant→cluster bucket map is read by the gateway
# itself from the `tenants.home_cluster` column; Front Door sends every
# request to whichever cluster's gateway can serve it (the gateway
# returns 307 redirect to the tenant's home cluster if it doesn't own
# that tenant).

resource "azurerm_cdn_frontdoor_profile" "mcp" {
  name                = "mcp-runtimeai-fd"
  resource_group_name = var.resource_group
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "mcp" {
  name                     = "mcp-runtimeai"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.mcp.id
}

resource "azurerm_cdn_frontdoor_origin_group" "mcp_clusters" {
  name                     = "mcp-clusters"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.mcp.id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/healthz"
    request_type        = "GET"
    protocol            = "Https"
    interval_in_seconds = 10
  }

  session_affinity_enabled = true # sticky-by-cookie at FD layer
}

# Per-cluster origin. Priority drives D2 (hot/warm) failover order.
resource "azurerm_cdn_frontdoor_origin" "rt19" {
  name                          = "rt19"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.mcp_clusters.id
  host_name                     = "mcp.rt19.runtimeai.io"
  http_port                     = 80
  https_port                    = 443
  origin_host_header            = "mcp.rt19.runtimeai.io"
  priority                      = 1
  weight                        = 100
  enabled                       = true
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_origin" "rt01" {
  name                          = "rt01"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.mcp_clusters.id
  host_name                     = "mcp.rt01.runtimeai.io"
  http_port                     = 80
  https_port                    = 443
  origin_host_header            = "mcp.rt01.runtimeai.io"
  priority                      = 1
  weight                        = 100
  enabled                       = true
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_origin" "rt02" {
  name                          = "rt02"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.mcp_clusters.id
  host_name                     = "mcp.rt02.runtimeai.io"
  http_port                     = 80
  https_port                    = 443
  origin_host_header            = "mcp.rt02.runtimeai.io"
  priority                      = 1
  weight                        = 100
  enabled                       = true
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "mcp" {
  name                          = "mcp-default"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.mcp.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.mcp_clusters.id
  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.rt19.id,
    azurerm_cdn_frontdoor_origin.rt01.id,
    azurerm_cdn_frontdoor_origin.rt02.id,
  ]
  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = false
  cdn_frontdoor_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.mcp.id]
}

resource "azurerm_cdn_frontdoor_custom_domain" "mcp" {
  name                     = "mcp-runtimeai-io"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.mcp.id
  host_name                = "mcp.runtimeai.io"

  tls {
    certificate_type    = "ManagedCertificate"
    minimum_tls_version = "TLS12"
  }
}
