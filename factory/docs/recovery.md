# Power-YT Fabric — Recovery

Сценарии отказа. Каждый: симптомы → диагностика → восстановление → ETA.

## 1. mgmt-eu полностью down (primary control-plane)

**Симптомы:**
- Алёрт `NetBirdMgmtDown` и/или `PostgresPrimaryDown`
- Grafana dashboard `Overview` показывает `mgmt-eu-1` down
- Новый peer не может зарегистрироваться (`netbird up` зависает)
- Существующие туннели ПРОДОЛЖАЮТ работать (mgmt не на data-path)

**Диагностика (1-3 мин):**
```bash
# 1. Доступ к mgmt-eu (физически) — ping, ssh, провайдер
ssh mgmt-eu-1 'systemctl status docker'
# 2. Если SSH работает — проверить контейнеры:
ssh mgmt-eu-1 'docker ps; docker logs keycloak --tail 50'
# 3. Если VPS не отвечает — провайдер dashboard
```

**Восстановление:**

### Если VPS живая, упал только сервис
```bash
ssh mgmt-eu-1
docker compose -f ~/auth/docker-compose.yml -f ~/auth/docker-compose.prod.yml \
  --profile core restart
docker compose -f ~/factory/netbird/docker-compose.yml restart
# Алёрт NetBirdMgmtDown резолвится за 60s.
```
**ETA: 5 мин.**

### Если VPS мертва — failover на cdn (Phase 6)

```bash
# 1. CF Load Balancer автоматически переключил DNS (использует use_load_balancer=true).
#    Проверить: dig +short login.<domain> nb.<domain>
#    → должно показать cdn IP (а не mgmt-eu).

# 2. Если use_load_balancer=false (ручной режим):
cd factory/dns
sed -i 's/mgmt_eu_ip/cdn_ip/' variables.tfvars
terraform apply

# 3. На cdn promote postgres standby:
ssh cdn
docker compose -f factory/replica/docker-compose.yml exec pg-standby \
  bash -c 'pg_ctl promote -D /var/lib/postgresql/data'

# 4. Поднять keycloak-replica (профиль failover):
docker compose -f factory/replica/docker-compose.yml --profile failover up -d

# 5. NetBird на cdn — restore из sqlite snapshot (Phase 6 systemd-timer должен
# был обновлять последнюю копию):
docker run --rm -d --name nb-management-recovery \
  -v factory-replica_pg-standby-data:/var/lib/netbird ... # restart NB-stack с реплицированной db
```
**ETA: 5-10 мин для CF DNS-LB, 15-30 мин для ручного режима + promote.**

### Когда mgmt-eu вернётся
```bash
# 1. На mgmt-eu отыграть с потерянными данными:
ssh mgmt-eu-1
pg_basebackup --host=cdn.netbird.fabric --port=5432 \
  --username=replicator --pgdata=/tmp/restore --wal-method=stream

# 2. После applies — cdn standby обратно стартует с mgmt-eu как primary.
# 3. CF LB автоматически возвращает primary в pool.
```

---

## 2. Один exit down

**Симптомы:** алёрт `NodeDown{peer="exit-de"}`, Grafana показывает single exit down.

**Восстановление: автоматическое.**

BGP withdraw → RR пересчитывает best-path → user-трафик уходит через
`exit-nl` (local-pref 150). **ETA: 60-90s.**

Если exit-узел нужен снова — `terraform apply` пересоздаёт VPS (Phase 5).
Иначе — `terraform destroy -target=<resource>` и удалить из inventory.

---

## 3. NetBird mgmt crashed (только NetBird, без mgmt-eu полного отказа)

**Симптомы:** новые peers не подключаются, существующие — работают.

**Диагностика:**
```bash
ssh mgmt-eu-1 docker logs nb-management --tail 100
```

**Восстановление:**
```bash
ssh mgmt-eu-1
docker compose -f ~/factory/netbird/docker-compose.yml restart
# Если store.db corrupted — restore из последнего systemd-snapshot:
docker run --rm -v netbird_mgmt-data:/dst busybox \
  cp /backups/netbird-$(date +%F).sqlite /dst/store.db
```
**ETA: 5 мин.**

---

## 4. AmneziaWG DPI-detection (туннели массово отваливаются)

**Симптомы:**
- Множественные `AmneziaWgHandshakeStale` алёрты одновременно
- Из РФ-сегментов нет связи с mgmt-eu/exits

**Диагностика:**
```bash
# С одного из affected peers
awg show
# last handshake = N ago. Должно быть <2min.
# tcpdump -i ens19 udp port <awg_port> — есть ли пакеты вообще?
```

**Восстановление:**

Ротация obfs-params (см. [runbook.md §4](runbook.md#4-регенерация-amneziawg-obfs-params)):
```bash
# Сгенерировать новые случайные Jc/Jmin/Jmax/S1/S2/Hx
# Обновить factory/ansible/group_vars/all.yml
git commit -am "fabric: rotate AWG obfs (DPI evasion incident)" && git push
gh workflow run factory-deploy.yml -f target=all -f tags=base

# Внимание: 30-60s простоя всех туннелей.
# Если ВСЕ peers отрезаны от GH/SSH — fallback на cdn-xray-portal (доступ
# через https://login.<domain>/oauth2/auth → forward-auth → web-shell или
# emergency-VPN на dedicated порт).
```
**ETA: 30 мин (если есть запасной канал доступа), часы (если нет).**

---

## 5. cdn-VDS заблокирован

**Симптомы:** public-домены `media.<domain>`, `seerr.<domain>` недоступны
снаружи РФ; admin-сервисы тоже unreachable (forward-auth не работает).

**Восстановление:**

```bash
# Вариант A — переключить Traefik media-routing на mgmt-eu (если порты Cloudflare
# доступны):
# В Cloudflare zone <domain>: A-записи media.* → mgmt-eu IP (вместо cdn)
# Внутри Traefik mgmt-eu добавить роутеры media-* (rsync конфига с cdn).

# Вариант B — поднять резервный cdn через Terraform (Phase 5 стиль, но не exit):
cd factory/terraform
# Добавить новый ресурс cdn2 (Hetzner DE или другой провайдер) с тем же
# cloud-init + bootstrap factory-deploy на role gw + перепривязать DNS
```
**ETA: 1-3 часа (новый VPS + конфиг Traefik).**

---

## 6. FRR на одном peer завис

**Симптомы:** один peer показывает 0 BGP-сессий в `vtysh show bgp summary`,
EVPN routes отсутствуют.

**Восстановление:**
```bash
ssh <peer>
systemctl restart frr
# EVPN routes реконвергируют с RR за 30-60s.
# Если не помогает — flush ip route + restart:
ip route flush proto bgp
systemctl restart frr
```
**ETA: 2 мин.**

---

## 7. Postgres streaming lag растёт

**Симптомы:** `PostgresReplicationLag > 300s` алёрт.

**Диагностика:**
```bash
# На primary (mgmt-eu):
docker exec keycloak-db psql -U postgres -c \
  "SELECT * FROM pg_stat_replication;"
# replay_lag, write_lag, flush_lag — если все > 5min, что-то не так.

# На standby (cdn):
docker exec pg-standby psql -U postgres -c \
  "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"
```

**Восстановление:**
- Если network bottleneck (overlay slow) — проверить AmneziaWG iperf3
- Если standby не справляется — увеличить standby ресурсы
- Если replication slot заполнил wal_keep_size — пересоздать standby:
  ```bash
  ssh cdn
  docker compose -f factory/replica/docker-compose.yml down
  docker volume rm factory-replica_pg-standby-data
  docker compose -f factory/replica/docker-compose.yml up -d
  # bootstrap-standby.sh заново сделает pg_basebackup
  ```
**ETA: 30 мин для re-bootstrap.**
