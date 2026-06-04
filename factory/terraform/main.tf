# ═══════════════════════════════════════════════════════════════════════
#  Terraform: lifecycle exit-VPS (Hetzner / Vultr / Linode).
#  Ansible принимает эстафету после первой загрузки через cloud-init.
#
#  Usage:
#    cp variables.tfvars.example variables.tfvars  &&  заполнить API-токены и ssh key
#    terraform init
#    terraform plan -var-file=variables.tfvars
#    terraform apply -var-file=variables.tfvars
#
#  После apply: получаешь IP-адреса exits → переносишь в
#  factory/ansible/inventory.yml → ansible-playbook playbooks/bootstrap.yml
#  --limit exit-de,exit-nl,exit-jp
# ═══════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21"
    }
    linode = {
      source  = "linode/linode"
      version = "~> 2.16"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "vultr" {
  api_key = var.vultr_api_key
}

provider "linode" {
  token = var.linode_token
}
