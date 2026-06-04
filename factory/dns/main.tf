# ═══════════════════════════════════════════════════════════════════════
#  Cloudflare DNS-failover для active-passive HA (Phase 6).
#  Load Balancer с health-checks на /health/ready primary → automatic failover.
#
#  ВНИМАНИЕ: Cloudflare Load Balancer — платная функция (~$5/mo на 500k DNS-запросов).
#  Альтернатива бесплатно: 2x A-record + monitoring + ручной cf-API switch при отказе
#  (TTL 60s даёт recovery ~120s).
#
#  Usage:
#    cp variables.tfvars.example variables.tfvars
#    terraform init && terraform apply -var-file=variables.tfvars
# ═══════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
  }
}

provider "cloudflare" {
  api_token = var.cf_api_token
}
