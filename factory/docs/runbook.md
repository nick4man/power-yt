# Power-YT Fabric — Runbook

Шпаргалка ежедневных операций. Полная архитектура — [architecture.md](architecture.md).
Сценарии отказа — [recovery.md](recovery.md).

## Содержание

1. [Добавить новый peer](#1-добавить-новый-peer)
2. [Ротировать exit-узел](#2-ротировать-exit-узел)
3. [Деплой изменения IaC](#3-деплой-изменения-iac)
4. [Регенерация AmneziaWG obfs-params](#4-регенерация-amneziawg-obfs-params)
5. [Добавить новый сервис в SSO](#5-добавить-новый-сервис-в-sso)
6. [Просмотр метрик и алёртов](#6-просмотр-метрик-и-алёртов)
7. [Бэкап realm и state](#7-бэкап-realm-и-state)

---

## 1. Добавить новый peer

Сценарий: появилась новая VM в Proxmox-2 (`home-server-2`), хочешь её в фабрику.

```bash
# 1. На NetBird UI (https://nb.<domain>): Setup Keys → New
#    Имя: home-server-2-bootstrap, тип: One-time, expiry: 1h. Скопируй setup-key.

# 2. В factory/ansible/inventory.yml — добавить:
#    home-server-2:
#      ansible_host: 192.168.0.X
#      ansible_user: root
#      fabric_loopback: 10.255.0.7
#      fabric_role: member
#      announced_vnis: [home, admin]

git add factory/ansible/inventory.yml
git commit -m "fabric: add peer home-server-2"
git push

# 3. На GitHub → Actions → factory-deploy → Run workflow:
#    target: home-server-2
#    tags:   base,gw,evpn
#    dry_run: false
#    + extra-var NETBIRD_SETUP_KEY=<setup-key>

# 4. Проверить:
ssh home-server-2 'netbird status; vtysh -c "show bgp l2vpn evpn summary"'
# В NetBird UI peer появится в Connected.
```

## 2. Ротировать exit-узел

Сценарий: exit-de заблокирован/просрочен/конкретно достал.

```bash
# 1. Создать новый exit через Terraform:
cd factory/terraform
# Включить exit-fr (новый):
echo 'exit_fr_enabled = true' >> variables.tfvars
terraform apply -var-file=variables.tfvars

# 2. Взять IP из output:
NEW_IP=$(terraform output -json exit_ips | jq -r '."exit-fr"')

# 3. Добавить в factory/ansible/inventory.yml:
#    exit-fr:
#      ansible_host: $NEW_IP
#      ...
#      bgp_local_pref: 175      # между de(200) и nl(150) — нагнал на середину

# 4. Bootstrap нового exit:
gh workflow run factory-deploy.yml -f target=exit-fr -f tags=base,gw,exit

# 5. Drain старого:
ansible-playbook factory/ansible/playbooks/rotate-exit.yml \
  -e action=drain -e target=exit-de

# 6. Удалить exit-de из inventory и через Terraform:
terraform destroy -target=hcloud_server.exit_de -var-file=variables.tfvars
git add factory/ansible/inventory.yml factory/terraform/
git commit -m "fabric: rotate exit-de → exit-fr"
git push
```

## 3. Деплой изменения IaC

```bash
# Один peer, конкретный role:
gh workflow run factory-deploy.yml -f target=home-rzn-gw -f tags=evpn

# Группа:
gh workflow run factory-deploy.yml -f target=gateways -f tags=evpn

# Dry-run (предпросмотр без применения):
gh workflow run factory-deploy.yml -f target=all -f tags=all -f dry_run=true
```

## 4. Регенерация AmneziaWG obfs-params

Сценарий: DPI прижала. Меняем obfs-pattern.

```bash
# 1. Сгенерировать новые случайные значения (Jc/Jmin/Jmax/S1/S2/Hx).
# Шаблон значений из Amnezia desktop client (Settings → Advanced → Generate).

# 2. Обновить factory/ansible/group_vars/all.yml — новые awg_* значения.

# 3. Закоммитить + задеплоить ВСЕМ ОДНОВРЕМЕННО:
git add factory/ansible/group_vars/all.yml
git commit -m "fabric: rotate AmneziaWG obfs-params (DPI evasion)"
git push
gh workflow run factory-deploy.yml -f target=all -f tags=base

# 4. Внимание: на 30-60 сек все туннели падают. Это ОЖИДАЕМО.
#    После применения везде — handshake восстановится с новыми obfs.

# 5. Если retry не сошёлся (peer недоступен) — заходим напрямую через NetBird
#    overlay (другой канал) и руками: systemctl restart awg-quick@*.
```

## 5. Добавить новый сервис в SSO

Сценарий: завели Vaultwarden, хотим SSO через `family`.

```bash
# 1. В Keycloak UI: realm family → Clients → Create
#    Client ID: vaultwarden
#    Standard flow: yes; Direct grants: no
#    Valid redirect URIs: https://vault.example.com/identity/connect/oidc-signin

# 2. Скопировать Client Secret (Credentials tab).

# 3. Создать factory/identity/vaultwarden/oidc-config.snippet (по шаблону
#    factory/identity/seerr/) с placeholder'ами + инструкцией.

# 4. Экспорт realm family (UI → realm-settings → Action → Partial export):
#    Сохранить новый client → auth/realms/family.json (заменить раздел clients).

# 5. Применить snippet на хосте Vaultwarden.

# 6. Закоммитить:
git add factory/identity/vaultwarden/ auth/realms/family.json
git commit -m "feat(factory): + Vaultwarden OIDC через family realm"
git push
```

## 6. Просмотр метрик и алёртов

```bash
# Grafana → https://grafana.<domain> (после Phase 7 OIDC)
# Dashboard "Power-YT Fabric — Overview" — основной обзор:
#   - Peer availability
#   - BGP peer state
#   - EVPN VNI count
#   - AmneziaWG handshake age
#   - Postgres replication lag
#   - NetBird connected peers
#   - Host CPU %

# Активные алёрты:
curl -fsS http://alertmanager.<domain>:9093/api/v2/alerts | jq

# Тест Telegram-бота (отправить fake-alert):
curl -X POST http://alertmanager:9093/api/v2/alerts \
  -d '[{"labels":{"alertname":"TestAlert","severity":"critical"}}]'
```

## 7. Бэкап realm и state

```bash
# Keycloak realm-export (на mgmt-eu):
docker exec keycloak /opt/keycloak/bin/kc.sh export \
  --dir /opt/keycloak/data/export --realm factory-admin
docker cp keycloak:/opt/keycloak/data/export/factory-admin-realm.json \
  ./auth/realms/factory-admin.json

# То же для family:
docker exec keycloak /opt/keycloak/bin/kc.sh export \
  --dir /opt/keycloak/data/export --realm family
docker cp keycloak:/opt/keycloak/data/export/family-realm.json \
  ./auth/realms/family.json

# Postgres pg_dump (полный backup KC + NetBird db):
docker exec keycloak-db pg_dumpall -U keycloak > backups/pg-$(date +%F).sql

# NetBird store.db (sqlite snapshot):
docker exec nb-management cp /var/lib/netbird/store.db /tmp/store.snap
docker cp nb-management:/tmp/store.snap backups/netbird-$(date +%F).sqlite
```

Закоммитить обновлённые realm-export в репо — это IaC-источник правды.
