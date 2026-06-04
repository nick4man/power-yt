#cloud-config
# Cloud-init для exit-VPS фабрики.
# Делает базовую подготовку + bootstrap NetBird. Дальше всё доделает Ansible.

package_update: true
package_upgrade: true

packages:
  - curl
  - jq
  - chrony
  - nftables
  - python3
  - python3-apt        # для Ansible ansible.builtin.apt
  - ca-certificates
  - gnupg

write_files:
  - path: /etc/sysctl.d/10-fabric-exit.conf
    content: |
      # Fabric exit defaults — оптимизация под high-throughput TCP через obfs-туннели.
      net.ipv4.ip_forward = 1
      net.ipv6.conf.all.forwarding = 1
      net.ipv4.tcp_congestion_control = bbr
      net.core.default_qdisc = fq
      net.core.somaxconn = 4096
      net.ipv4.tcp_max_syn_backlog = 4096
      net.ipv4.tcp_fastopen = 3
      net.ipv4.conf.all.rp_filter = 2
      net.ipv4.conf.default.rp_filter = 2
    permissions: '0644'

runcmd:
  # 1. Применить sysctl
  - sysctl --system

  # 2. NetBird repo + установка (Debian/Ubuntu путь)
  - curl -fsSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor -o /usr/share/keyrings/netbird-archive-keyring.gpg
  - echo "deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main" > /etc/apt/sources.list.d/netbird.list
  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y netbird

  # 3. Регистрация в NetBird mgmt (если setup-key передан)
  - |
    if [ -n "${netbird_setup_key}" ]; then
      netbird up --setup-key "${netbird_setup_key}" --management-url "${netbird_mgmt_url}" || true
    fi

  # 4. Включить + запустить chrony (NTP — для BGP-таймеров)
  - systemctl enable --now chrony

final_message: "Exit-VPS готов. Следующий шаг: ansible-playbook playbooks/bootstrap.yml --limit <hostname>"
