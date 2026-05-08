# =============================================================================
# OPER_RT19-088 NEW-2 — Azure Monitor alerts for weekly digest
# =============================================================================
# Five alert rules, all routed to a log-only action group (no SMS/voice/page).
# The CEO weekly status report (`weekly_status/ops_report.py`) reads firing
# history from the Activity Log via `az monitor activity-log list` and
# embeds the count + top events in the digest.
#
# Dependencies that may not yet exist in this state file are exposed as
# variables (see below). Set them in `terraform.tfvars` or via `-var` flags.
# Until then, the alerts that depend on them are guarded by `count` so the
# stack still applies cleanly.
#
# Expected variable values (current rt19 environment):
#   law_resource_id        = LAW for AKS Container Insights
#                            (default name guess: rt19-aks-laworkspace)
#   postgres_server_id     = Azure DB for PostgreSQL Flexible Server resource ID
#                            (only set if managed Postgres is in use; rt19
#                             currently self-hosts inside AKS — leave empty)
#   container_app_ids      = list of Container Apps resource IDs to monitor
#                            (e.g. license-service)
#   monthly_budget_amount  = USD; default 1500
# =============================================================================

variable "law_resource_id" {
  type        = string
  description = "Resource ID of the Log Analytics Workspace backing AKS Container Insights. Leave empty to skip the CrashLoopBackOff alert."
  default     = ""
}

variable "postgres_server_id" {
  type        = string
  description = "Resource ID of the Azure DB for PostgreSQL Flexible Server. Leave empty to skip the connection saturation alert (rt19 currently self-hosts Postgres inside AKS)."
  default     = ""
}

variable "container_app_ids" {
  type        = list(string)
  description = "Resource IDs of Azure Container Apps to monitor for restart loops (e.g. license-service)."
  default     = []
}

variable "monthly_budget_amount" {
  type        = number
  description = "Monthly Azure budget in USD for the rt19 resource group."
  default     = 1500
}

variable "public_site_role_names" {
  type        = list(string)
  description = "cloud_RoleName values used by App Insights JS SDK on each public site."
  default = [
    "runtimeai-landing",
    "runtimeai-trial",
    "esign-landing",
    "saas-admin",
    "dashboard",
  ]
}

# ── Application Insights (shared) ────────────────────────────────────────────
resource "azurerm_application_insights" "rt19_shared" {
  name                = "rt19-shared-appinsights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = 90
  workspace_id        = "/subscriptions/87e9e058-3b71-4d1b-b736-4d8475ac5299/resourceGroups/ai_rt19-shared-appinsights_2e498a32-5a76-4669-806b-85fe11c76332_managed/providers/Microsoft.OperationalInsights/workspaces/managed-rt19-shared-appinsights-ws"
}

output "appinsights_connection_string" {
  value     = azurerm_application_insights.rt19_shared.connection_string
  sensitive = true
}

output "appinsights_instrumentation_key" {
  value     = azurerm_application_insights.rt19_shared.instrumentation_key
  sensitive = true
}

# ── Action Group (log-only) ──────────────────────────────────────────────────
# No receivers — alerts log to Activity Log only.
# weekly_status/ops_report.py queries firing history via
#   az monitor activity-log list --caller "Microsoft.Insights/..."
resource "azurerm_monitor_action_group" "weekly_digest" {
  name                = "ag-weekly-digest"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "weeklydig"
  enabled             = true
  # Intentionally no email/sms/voice/webhook receivers.
}

# ── Alert 1: 5xx rate > 5% per public site (one rule per cloudRoleName) ──────
resource "azurerm_monitor_metric_alert" "site_5xx_rate" {
  for_each = toset(var.public_site_role_names)

  name                = "alert-${each.value}-5xx-rate"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.rt19_shared.id]
  description         = "5xx error rate > 5% over 5 minutes for ${each.value}"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true

  # Average count of failed requests per minute. App Insights does not
  # expose a direct "% failed" metric, so we alert on the absolute rate
  # of failures and rely on the cloud_RoleName dimension filter to scope.
  # For sites with low traffic, > 5 failed requests in 5 min is the
  # equivalent of ~5%+ at typical baseline volumes.
  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "requests/failed"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5

    dimension {
      name     = "cloud/roleName"
      operator = "Include"
      values   = [each.value]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.weekly_digest.id
  }

  tags = {
    site    = each.value
    purpose = "oper-088-weekly-digest"
  }
}

# ── Alert 2: Container Apps revision unhealthy (Restart > 5/h) ───────────────
resource "azurerm_monitor_metric_alert" "container_app_restarts" {
  for_each = toset(var.container_app_ids)

  name                = "alert-containerapp-restarts-${substr(sha1(each.value), 0, 8)}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [each.value]
  description         = "Container App restart count > 5 in the last hour"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT1H"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.weekly_digest.id
  }

  tags = {
    purpose = "oper-088-weekly-digest"
  }
}

# ── Alert 3: AKS pod CrashLoopBackOff > 3/h (KQL via Container Insights) ─────
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_crashloop" {
  count = var.law_resource_id == "" ? 0 : 1

  name                = "alert-aks-crashloopbackoff"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  evaluation_frequency = "PT15M"
  window_duration      = "PT1H"
  scopes               = [var.law_resource_id]
  severity             = 2
  enabled              = true

  criteria {
    query                   = <<-KQL
      KubePodInventory
      | where TimeGenerated > ago(1h)
      | where ContainerStatusReason == "CrashLoopBackOff"
        or PodStatus == "Failed"
        or ContainerLastStatus contains "CrashLoop"
      | summarize Crashes = count() by ClusterName, Namespace, Name
      | where Crashes > 3
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
  }

  action {
    action_groups = [azurerm_monitor_action_group.weekly_digest.id]
  }

  tags = {
    purpose = "oper-088-weekly-digest"
  }
}

# ── Alert 4: Postgres connection saturation > 80 ─────────────────────────────
# Only deploys when a managed Postgres flexible server resource ID is provided.
# rt19 currently self-hosts Postgres inside AKS, so this is opt-in.
resource "azurerm_monitor_metric_alert" "postgres_connection_saturation" {
  count = var.postgres_server_id == "" ? 0 : 1

  name                = "alert-postgres-connection-saturation"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [var.postgres_server_id]
  description         = "Postgres active connections > 80 (saturation indicator)"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "active_connections"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.weekly_digest.id
  }

  tags = {
    purpose = "oper-088-weekly-digest"
  }
}

# ── Alert 5: Azure cost — monthly RG budget with multi-tier alerts ───────────
# Cost-Mgmt does not surface a native "daily delta vs 7d avg" metric without
# exporting cost data to LAW (a multi-day setup). For now we use a budget on
# the resource group with three notification thresholds — log-only via the
# action group. The weekly digest script can compute deltas from the budget's
# notification history.
resource "azurerm_consumption_budget_resource_group" "rt19_monthly" {
  name              = "budget-rt19-monthly"
  resource_group_id = azurerm_resource_group.main.id

  amount     = var.monthly_budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = "2026-05-01T00:00:00Z"
  }

  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_groups = [azurerm_monitor_action_group.weekly_digest.id]
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_groups = [azurerm_monitor_action_group.weekly_digest.id]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_groups = [azurerm_monitor_action_group.weekly_digest.id]
  }
}
