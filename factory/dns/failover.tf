# ═══════════════════════════════════════════════════════════════════════
#  Failover для login.${fabric_domain} и nb.${fabric_domain}.
#
#  Два режима через variable use_load_balancer:
#    true  — Cloudflare Load Balancer с health-checks (платно, ~$5/mo)
#    false — два A-record + monitor + email notify (бесплатно, ручной cutover)
# ═══════════════════════════════════════════════════════════════════════

# ── Health monitor (общий для KC и NetBird) ──────────────────────────────
resource "cloudflare_load_balancer_monitor" "kc_health" {
  count          = var.use_load_balancer ? 1 : 0
  account_id     = var.cf_account_id
  type           = "https"
  description    = "Keycloak /health/ready"
  expected_codes = "200"
  path           = "/health/ready"
  port           = 443
  retries        = 1
  timeout        = 5
  interval       = 30
  method         = "GET"
  follow_redirects = false
  allow_insecure   = false
}

resource "cloudflare_load_balancer_monitor" "nb_health" {
  count          = var.use_load_balancer ? 1 : 0
  account_id     = var.cf_account_id
  type           = "https"
  description    = "NetBird /api/status"
  expected_codes = "200"
  path           = "/api/status"
  port           = 443
  retries        = 1
  timeout        = 5
  interval       = 30
  method         = "GET"
}

# ── Pools: primary (mgmt-eu) + backup (cdn) ──────────────────────────────
resource "cloudflare_load_balancer_pool" "mgmt_primary" {
  count       = var.use_load_balancer ? 1 : 0
  account_id  = var.cf_account_id
  name        = "mgmt-eu-primary"
  description = "Primary control-plane на mgmt-eu"
  enabled     = true
  origins {
    name    = "mgmt-eu-1"
    address = var.mgmt_eu_ip
    enabled = true
    weight  = 1
  }
  monitor = cloudflare_load_balancer_monitor.kc_health[0].id
}

resource "cloudflare_load_balancer_pool" "mgmt_backup" {
  count       = var.use_load_balancer ? 1 : 0
  account_id  = var.cf_account_id
  name        = "mgmt-cdn-backup"
  description = "Backup replica на cdn"
  enabled     = true
  origins {
    name    = "cdn"
    address = var.cdn_ip
    enabled = true
    weight  = 1
  }
  monitor = cloudflare_load_balancer_monitor.kc_health[0].id
}

# ── Load Balancers (login + nb) ──────────────────────────────────────────
resource "cloudflare_load_balancer" "login" {
  count            = var.use_load_balancer ? 1 : 0
  zone_id          = var.cf_zone_id
  name             = "login.${var.fabric_domain}"
  description      = "Keycloak — active/passive с failover на cdn"
  default_pool_ids = [cloudflare_load_balancer_pool.mgmt_primary[0].id]
  fallback_pool_id = cloudflare_load_balancer_pool.mgmt_backup[0].id
  proxied          = false   # без CF proxy: KC видит реальный client IP для audit
  steering_policy  = "off"   # off = default_pool пока healthy → fallback
  ttl              = 30
}

resource "cloudflare_load_balancer" "nb" {
  count            = var.use_load_balancer ? 1 : 0
  zone_id          = var.cf_zone_id
  name             = "nb.${var.fabric_domain}"
  description      = "NetBird Management — active/passive"
  default_pool_ids = [cloudflare_load_balancer_pool.mgmt_primary[0].id]
  fallback_pool_id = cloudflare_load_balancer_pool.mgmt_backup[0].id
  proxied          = false
  steering_policy  = "off"
  ttl              = 30
}

# ── Альтернатива (бесплатно): 2x A-record с одинаковым TTL + ручной cutover ───
resource "cloudflare_record" "login_primary" {
  count   = var.use_load_balancer ? 0 : 1
  zone_id = var.cf_zone_id
  name    = "login"
  content = var.mgmt_eu_ip
  type    = "A"
  ttl     = 60
  proxied = false
  comment = "Primary mgmt-eu — при отказе вручную поменять content на cdn_ip"
}

resource "cloudflare_record" "nb_primary" {
  count   = var.use_load_balancer ? 0 : 1
  zone_id = var.cf_zone_id
  name    = "nb"
  content = var.mgmt_eu_ip
  type    = "A"
  ttl     = 60
  proxied = false
}

# При use_load_balancer=false — Phase 8 (observability) делает alert на KC health,
# Phase 9 (runbook) описывает ручной cf-API switch.
