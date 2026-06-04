# Готовый ансиблу-friendly inventory: ip-адреса каждого exit'а.
# Получить: terraform output -json exit_ips | jq

output "exit_ips" {
  description = "Публичные IPv4 каждого exit-узла (по имени)"
  value = {
    exit-de = try(hcloud_server.exit_de[0].ipv4_address, null)
    exit-nl = try(vultr_instance.exit_nl[0].main_ip, null)
    exit-jp = try(linode_instance.exit_jp[0].ip_address, null)
  }
}

output "exit_ipv6" {
  description = "Публичные IPv6 (если поддерживается провайдером)"
  value = {
    exit-de = try(hcloud_server.exit_de[0].ipv6_address, null)
    exit-nl = try(vultr_instance.exit_nl[0].v6_main_ip, null)
    exit-jp = try(linode_instance.exit_jp[0].ipv6, null)
  }
}

output "ansible_inventory_snippet" {
  description = "Готовый YAML-фрагмент для копи-паста в factory/ansible/inventory.yml"
  value = <<-EOT
    exits:
      hosts:
    %{ if var.exit_de_enabled ~}
        exit-de:
          ansible_host: ${try(hcloud_server.exit_de[0].ipv4_address, "MISSING")}
          ansible_user: root
          fabric_loopback: 10.255.0.10
          fabric_role: exit
          bgp_local_pref: 200
          announced_vnis: [admin]
    %{ endif ~}
    %{ if var.exit_nl_enabled ~}
        exit-nl:
          ansible_host: ${try(vultr_instance.exit_nl[0].main_ip, "MISSING")}
          ansible_user: root
          fabric_loopback: 10.255.0.11
          fabric_role: exit
          bgp_local_pref: 150
          announced_vnis: [admin]
    %{ endif ~}
    %{ if var.exit_jp_enabled ~}
        exit-jp:
          ansible_host: ${try(linode_instance.exit_jp[0].ip_address, "MISSING")}
          ansible_user: root
          fabric_loopback: 10.255.0.12
          fabric_role: exit
          bgp_local_pref: 100
          announced_vnis: [admin]
    %{ endif ~}
  EOT
}
