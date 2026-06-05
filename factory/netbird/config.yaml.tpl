# Рендерится render.sh (envsubst) → config.yaml (gitignored: реальный домен + секреты).
# Combined netbird-server v0.71+: management + signal + relay + STUN в одном.
#
# Auth — ВСТРОЕННЫЙ Dex IdP. Combined-контейнер НЕ поддерживает внешний IdP
# (netbird issue #5335: embedded Dex всегда включён и перекрывает HTTP auth-config).
# Юзеры NetBird — в embedded Dex; owner создаётся через setup-wizard дашборда
# при первом входе. Keycloak factory-admin — для ДРУГИХ сервисов (Jellyfin/Grafana/
# Proxmox поддерживают external OIDC), НЕ для NetBird.
server:
  listenAddress: ":80"
  exposedAddress: "https://nb.${FABRIC_DOMAIN}:443"
  stunPorts:
    - 3478
  metricsPort: 9090
  healthcheckAddress: ":9000"
  logLevel: "info"
  logFile: "console"

  # Relay-аутентификация (нативный TURN-replacement). openssl rand -base64 32.
  authSecret: "${NETBIRD_RELAY_AUTH_SECRET}"
  dataDir: "/var/lib/netbird"

  auth:
    # Встроенный Dex на /oauth2 (edge роутит /oauth2 → netbird-server:80).
    issuer: "https://nb.${FABRIC_DOMAIN}/oauth2"
    localAuthDisabled: false
    signKeyRefreshEnabled: true
    dashboardRedirectURIs:
      - "https://nb.${FABRIC_DOMAIN}/nb-auth"
      - "https://nb.${FABRIC_DOMAIN}/nb-silent-auth"
    cliRedirectURIs:
      - "http://localhost:53000/"

  reverseProxy:
    # Доверяем X-Forwarded от edge-Traefik. 172.30.0.0/24 — docker-сеть netbird.
    trustedHTTPProxies:
      - "172.30.0.0/24"

  store:
    engine: "sqlite"
    encryptionKey: "${DATASTORE_ENCRYPTION_KEY}"
