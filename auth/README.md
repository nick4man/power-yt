# Auth-стек: Keycloak + oauth2-proxy (forward-auth для media-стека)

Запускается на **отдельной (третьей) машине**, входящей в WireGuard-сеть `10.10.0.0/24`.
Защищает admin-приложения media-стека единым входом (SSO) через Traefik(VDS) forward-auth.

```
браузер → media.example.com/<app> → Traefik(VDS)
        → forwardAuth → oauth2-proxy(third:4180)  [нет сессии?]
        → редирект → Keycloak(login.example.com) → логин → cookie .example.com → доступ
```

Jellyfin/Seerr НЕ закрываем (своя авторизация + клиенты не умеют SSO-редирект).

## 1. Подготовка третьей машины
- Docker + Compose, входит в WG (`10.10.0.0/24`), знает свой WG-адрес.
- Порт WG-адреса достижим с VDS (проверить: с VDS `ping <THIRD_WG>`).

## 2. Конфигурация
```bash
cp .env.example .env
# заполнить: BIND_IP=<WG-адрес этой машины>, пароли, секреты:
#   KC_DB_PASSWORD       = openssl rand -hex 16
#   KC_ADMIN_PASSWORD    = надёжный
#   OAUTH2_COOKIE_SECRET = openssl rand -base64 32
#   OAUTH2_CLIENT_SECRET = заполнить ПОСЛЕ шага 4 (из Keycloak)
```

## 3. Запуск Keycloak (+ DNS)
```bash
docker compose up -d keycloak-db keycloak
```
- DNS: `login.example.com` → белый IP VDS (Cloudflare A-запись).
- На VDS залить `traefik-auth-snippet.yml` в `/config` (заменив `<THIRD_WG>`), чтобы
  `https://login.example.com` открывал Keycloak (серт — Cloudflare DNS-01).

## 4. Настройка Keycloak (веб-админка login.example.com)
1. Войти как `KC_ADMIN_USER`.
2. Создать **Realm** `media`.
3. **Clients → Create**: Client ID `media-proxy`, тип **OpenID Connect**, **Client authentication = On**
   (confidential), Standard flow.
   - **Valid redirect URIs**: `https://*.example.com/oauth2/callback` и `https://media.example.com/oauth2/callback`
   - **Web origins**: `https://media.example.com` (или `+`).
4. **Clients → media-proxy → Credentials** → скопировать **Client secret** → в `.env` `OAUTH2_CLIENT_SECRET`.
5. Завести пользователей (Users) / при желании группы и политики.

## 5. Запуск oauth2-proxy
```bash
docker compose up -d oauth2-proxy
docker logs oauth2-proxy   # должен подключиться к issuer https://login.example.com/realms/media
```

## 6. Включить защиту на Traefik (VDS)
В `traefik-media.example.com.yml` (на VDS) у admin-роутеров заменить:
```
middlewares: [basic-auth@file]   →   middlewares: [media-forward-auth@file]
```
для: media-sonarr/radarr/lidarr/whisparr/prowlarr/bazarr/cleanuparr/jellystat/tdarr/qbittorrent.
`/oauth2`-роутеры уже добавлены в `traefik-auth-snippet.yml`. После заливки — открыть любой
admin-URL: должно редиректить на Keycloak, после входа — пускать.

## Проверка
- `https://login.example.com` — страница Keycloak, валидный серт.
- `https://media.example.com/sonarr` без сессии → редирект на Keycloak → после логина → Sonarr.
- Один вход открывает все admin-приложения (SSO, cookie на `.example.com`).

## Заметки
- Cookie-домен `.example.com` → одна сессия на все поддомены и пути.
- MFA/политики — в Keycloak (Authentication flows, Required actions).
- Если нужен OIDC-логин в самом Jellyfin — это отдельно (плагин SSO для Jellyfin + client в Keycloak),
  не через forward-auth.

---

## CI/CD — миграция через GitHub Actions

Workflow: `.github/workflows/auth-ci.yml`. Два этапа:
- **validate** — на каждый push/PR в `auth/**`: `docker compose config` для эмуляции и для прод-оверрайда (без секретов).
- **deploy** — по `workflow_dispatch` или push в `main`: SSH на третью машину, `rsync` файлов (без `data/`, `.env`, `*.sh`, `traefik-edge/`), генерация `.env` из секретов, `docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile core up -d`, smoke-тест (ждём «OAuthProxy configured»).

Деплой защищён GitHub Environment `production` (рекомендуется включить required reviewers).

### Требуемые GitHub Secrets
| Secret | Назначение |
|---|---|
| `THIRD_HOST` | адрес третьей машины (SSH) |
| `THIRD_USER` | SSH-пользователь |
| `THIRD_SSH_PORT` | порт SSH (опц., по умолчанию 22) |
| `THIRD_SSH_KEY` | приватный SSH-ключ деплоя |
| `THIRD_WG_IP` | WG-адрес 3-й машины → `BIND_IP` (на него VDS-Traefik ходит) |
| `KC_DB_PASSWORD` | пароль Postgres Keycloak |
| `KC_ADMIN_USER` / `KC_ADMIN_PASSWORD` | bootstrap-админ Keycloak |
| `OAUTH2_CLIENT_ID` | id клиента (media-proxy) |
| `OAUTH2_CLIENT_SECRET` | секрет клиента из Keycloak |
| `OAUTH2_COOKIE_SECRET` | cookie-секрет (16/24/32 байта) |

Прод-значения доменов зашиты в workflow: `login.example.com`, issuer `https://login.example.com/realms/media`, `COOKIE_DOMAIN=.example.com`.

### Что вне CI (одноразово, на проде)
1. DNS: `login.example.com` → белый IP VDS (Cloudflare).
2. VDS-Traefik: залить `traefik-auth-snippet.yml` (заменив `<THIRD_WG>`), переключить admin-роутеры `basic-auth@file → media-forward-auth@file`.
3. В Keycloak realm `media`: создать клиент `media-proxy` (redirect `https://*.example.com/oauth2/callback`) и пользователей. Локальный стенд это уже делает скриптом — на проде повторить через admin API/UI.
