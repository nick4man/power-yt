variable "cf_api_token" {
  description = "Cloudflare API token (Zone:DNS:Edit + Account:Load Balancers:Edit)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cf_account_id" {
  description = "Cloudflare Account ID (для Load Balancer pools/monitors)"
  type        = string
  default     = ""
}

variable "cf_zone_id" {
  description = "Cloudflare Zone ID для FABRIC_DOMAIN"
  type        = string
  default     = ""
}

variable "fabric_domain" {
  description = "Корневой домен фабрики (без поддомена)"
  type        = string
  default     = "example.com"
}

variable "mgmt_eu_ip" {
  description = "Public IP primary mgmt-eu"
  type        = string
  default     = ""
}

variable "cdn_ip" {
  description = "Public IP backup cdn"
  type        = string
  default     = ""
}

variable "use_load_balancer" {
  description = "Использовать платный Cloudflare Load Balancer (true) или 2x A-record с ручным failover (false)"
  type        = bool
  default     = true
}
