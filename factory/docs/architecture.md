# Power-YT Fabric — архитектура

Это полная картина — для нового админа, для дискуссий с собой через 6 месяцев,
для понимания «почему оно так». Для ежедневных операций смотри [runbook.md](runbook.md).
Для отказов — [recovery.md](recovery.md).

## Назначение

Гетерогенная распределённая инфра под жёстким DPI/блокировками. Что было больно:

1. РФ-сегменты не могут достать собственный cdn-VDS даже в Москве.
2. Office ↔ Home ↔ IoT — нужен межсайтовый L2 (mDNS, SMB, RDP, IoT-broadcast).
3. Exit-точки заменяются неделями/месяцами — статика-конфиги сломаются.
4. Идентичность: единый SSO для админов сети + Proxmox + раздельный для семейного контура.
5. Стек должен расти: новый узел = одна команда, не правка N конфигов.

## Слои (Layer cake)

```
┌──────────────────────────────────────────────────────────────────────┐
│  Identity        Keycloak (factory-admin + family realms)            │
│  ↕                                                                   │
│  Membership      NetBird Management (OIDC через factory-admin)       │
│  ↕                                                                   │
│  Routing         FRR (iBGP + l2vpn-evpn, RR на mgmt-eu + cdn)        │
│  ↕                                                                   │
│  Overlay L2      Linux VXLAN VTEPs + bridges (per-VNI, EVPN-routed)  │
│  ↕                                                                   │
│  Underlay        AmneziaWG mesh (DPI-resistant point-to-point)       │
└──────────────────────────────────────────────────────────────────────┘
```

Каждый слой — своя ответственность:
- **AmneziaWG** даёт зашифрованную DPI-устойчивую связность peer↔peer.
- **NetBird** управляет членством (кто peer, какая identity, какой setup-key).
- **FRR** распространяет EVPN routes type-2 (MAC/IP) и type-3 (multicast VTEP discovery).
- **VXLAN+bridges** на каждом VTEP делают L2-encapsulation.
- **Keycloak** — корень identity для всего.

Если NetBird mgmt упал — туннели продолжают работать (mgmt не на data-path).
Если FRR на peer'е перезапустился — EVPN-таблица восстановится с RR.
Если AmneziaWG-параметры скомпрометированы DPI — ротация через `--tags awg`.

## Топология (как сейчас задумано)

```
                    ┌──────────────────────────────────────────────┐
   Internet ───────►│  cdn (Москва VDS, public)                    │
                    │  ├─ Traefik (HTTPS, CF cert)                 │
                    │  ├─ FRR (RR backup)                          │
                    │  ├─ Keycloak replica (Phase 6)               │
                    │  └─ AmneziaWG peer + xray-portal             │
                    └────────────────┬─────────────────────────────┘
                                     │
   ┌─── mgmt-eu (Hetzner DE, public) — primary control-plane ──────┐
   │  ├─ NetBird MGMT (PG primary)                                 │
   │  ├─ Keycloak primary (factory-admin + family)                 │
   │  ├─ FRR (RR primary)                                          │
   │  ├─ Prometheus + Alertmanager + Grafana (Phase 8)             │
   │  └─ AmneziaWG peer                                            │
   └──────────────────────────────────────────────────────────────┘
        │
        ├── office-msk-gw (Proxmox-1 VM) — анонсирует 192.168.10.0/24
        ├── home-rzn-gw   (Proxmox-2 VM) — анонсирует 192.168.0.0/24
        ├── iot-gw        — анонсирует IoT-сегмент
        ├── media-host    — участник VNI media (10.40.0.6)
        └── exit-N        — динамические anti-censorship exits
                            (local-pref 200/150/100, BGP best-path failover)
```

## Адресное пространство

| Назначение | Подсеть | Раздача |
|---|---|---|
| Underlay loopback (BGP router-id, VTEP source) | `10.255.0.0/24` | `.1=mgmt-eu, .2=cdn, .3=office-msk-gw, .4=home-rzn-gw, .5=iot-gw, .6=media-host, .10-19=exits` |
| AmneziaWG mesh (/30 pairs) | `10.254.0.0/16` | автогенерация в Ansible |
| VNI 10100 office | overlay `10.10.0.0/24` ↔ LAN `192.168.10.0/24` | office-msk-gw bridges |
| VNI 10200 home | overlay `10.20.0.0/24` ↔ LAN `192.168.0.0/24` | home-rzn-gw bridges, TrueNAS 192.168.0.12 |
| VNI 10300 iot | overlay `10.30.0.0/24` ↔ IoT-LAN | iot-gw bridges |
| VNI 10400 media | `10.40.0.0/24` | media-host + cdn + exits |
| VNI 10500 admin | `10.50.0.0/24` | управленческий контур, строгий ACL |
| AS-номер фабрики | `65000` (private) | iBGP RR-cluster на mgmt-eu + cdn |

## Trade-offs (что выбрали и почему)

| Развилка | Выбрали | Не выбрали (и почему) |
|---|---|---|
| Membership control-plane | NetBird self-hosted | Headscale (нет OIDC встроенно), pure WG-mesh (ручное peer-management при N узлах) |
| L2-stretch | Полная EVPN-фабрика | L3-only (нет mDNS/SMB-discovery), RouterOS CHR (лицензии $45/yr × N) |
| HA mgmt | Active-passive с CF DNS-failover | Multi-master KC (сложнее), single-instance (single point of failure) |
| Identity scope | Два realm: factory-admin + family | Один realm (PII mix), три realm (избыточно) |
| Obfuscation | AmneziaWG | OpenVPN-obfs (медленнее), Shadowsocks (не L3), WireGuard ванильный (DPI fingerprintable) |
| Под капотом NetBird WG | AmneziaWG binary swap (Phase 2.5) | Vanilla WG (ловит DPI), не swap'ить (нет obfs) |

## Что НЕ входит

- Multi-master HA Keycloak (active-passive достаточно)
- IPv6 в overlay (Phase 5+ опц)
- Per-flow zero-trust (фабрика-периметр + forward-auth для веб достаточно)
- SIEM/Loki (Phase 8+ опц)
- Backup KC realm экспорт по таймеру (опц после первого деплоя)

## Bus-factor

Один владелец. Митигация: всё в IaC (Ansible + Terraform), runbook покрывает
«новый админ через 6 месяцев получает inventory и поднимает с нуля». На случай
полной потери mgmt-eu — `factory/replica/` поднимает второй экземпляр на cdn.

## Контрольные документы

- [runbook.md](runbook.md) — ежедневные операции
- [recovery.md](recovery.md) — сценарии отказа
- `factory/identity/MAP.txt` — карта realm ↔ service ↔ group-ACL
- `factory/observability/prometheus/alerts.yml` — что мониторится и когда алёрт
