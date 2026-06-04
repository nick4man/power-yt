variable "hcloud_token" {
  description = "Hetzner Cloud API token (read+write)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vultr_api_key" {
  description = "Vultr API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "linode_token" {
  description = "Linode Personal Access Token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_key_name" {
  description = "Имя SSH-ключа, заранее загруженного в провайдеров"
  type        = string
  default     = "fabric-deploy"
}

variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу для inline-upload (резерв)"
  type        = string
  default     = "~/.ssh/fabric-deploy.pub"
}

variable "netbird_setup_key" {
  description = "NetBird single-use setup key для регистрации peer'а через cloud-init"
  type        = string
  sensitive   = true
  default     = ""
}

variable "netbird_mgmt_url" {
  description = "NetBird management URL (https://nb.<domain>)"
  type        = string
  default     = "https://nb.example.com"
}

variable "fabric_tag" {
  description = "Tag/label на ресурсах для фильтрации (показывает provider)"
  type        = string
  default     = "fabric-exit"
}

# ── Exit locations (включай/выключай через count в exits.tf) ─────────────
variable "exit_de_enabled"  { type = bool default = true  }
variable "exit_nl_enabled"  { type = bool default = true  }
variable "exit_jp_enabled"  { type = bool default = false }
