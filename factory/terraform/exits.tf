# ═══════════════════════════════════════════════════════════════════════
#  Exit-VPS для anti-censorship фабрики.
#  Каждый exit получает:
#    - публичный IPv4+IPv6
#    - cloud-init с базовой подготовкой + NetBird bootstrap
#    - SSH-доступ для Ansible (предзагруженный ключ)
# ═══════════════════════════════════════════════════════════════════════

# ── Cloud-init: единый template для всех провайдеров ─────────────────────
locals {
  cloud_init_user_data = templatefile("${path.module}/templates/cloud-init.yml.tpl", {
    netbird_setup_key = var.netbird_setup_key
    netbird_mgmt_url  = var.netbird_mgmt_url
  })
}

# ── Hetzner: exit-de (Falkenstein) ───────────────────────────────────────
data "hcloud_ssh_key" "fabric" {
  count = var.exit_de_enabled ? 1 : 0
  name  = var.ssh_key_name
}

resource "hcloud_server" "exit_de" {
  count       = var.exit_de_enabled ? 1 : 0
  name        = "exit-de"
  location    = "fsn1"
  image       = "debian-12"
  server_type = "cx22"
  ssh_keys    = [data.hcloud_ssh_key.fabric[0].id]
  user_data   = local.cloud_init_user_data
  labels = {
    fabric_role = "exit"
    region      = "eu"
    tag         = var.fabric_tag
  }
}

# ── Vultr: exit-nl (Amsterdam) ───────────────────────────────────────────
data "vultr_ssh_key" "fabric" {
  count = var.exit_nl_enabled ? 1 : 0
  filter {
    name   = "name"
    values = [var.ssh_key_name]
  }
}

resource "vultr_instance" "exit_nl" {
  count            = var.exit_nl_enabled ? 1 : 0
  label            = "exit-nl"
  hostname         = "exit-nl"
  region           = "ams"
  plan             = "vc2-1c-1gb"
  os_id            = 477          # Debian 12
  ssh_key_ids      = [data.vultr_ssh_key.fabric[0].id]
  user_data        = base64encode(local.cloud_init_user_data)
  enable_ipv6      = true
  ddos_protection  = false
  activation_email = false
  tags             = ["fabric-role-exit", "region-eu", var.fabric_tag]
}

# ── Linode: exit-jp (Tokyo) ──────────────────────────────────────────────
data "linode_sshkey" "fabric" {
  count = var.exit_jp_enabled ? 1 : 0
  label = var.ssh_key_name
}

resource "linode_instance" "exit_jp" {
  count            = var.exit_jp_enabled ? 1 : 0
  label            = "exit-jp"
  region           = "ap-northeast"
  type             = "g6-nanode-1"
  image            = "linode/debian12"
  authorized_keys  = [data.linode_sshkey.fabric[0].ssh_key]
  metadata {
    user_data = base64encode(local.cloud_init_user_data)
  }
  tags = ["fabric-role-exit", "region-ap", var.fabric_tag]
}
