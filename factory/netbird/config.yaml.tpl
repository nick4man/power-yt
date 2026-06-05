# Рендерится render.sh (envsubst) → config.yaml (gitignored: реальный домен + секреты).
# Combined netbird-server v0.71+: management + signal + relay + STUN в одном.
# Auth — ВНЕШНИЙ Keycloak realm factory-admin (НЕ встроенный Dex /oauth2).
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
    # Внешний Keycloak как IdP напрямую (issuer = realm). signKeyRefresh — ротация JWKS.
    issuer: "https://login.${FABRIC_DOMAIN}/realms/factory-admin"
    # audience — проверка claim `aud` в JWT. Совпадает с client `netbird` (audience-mapper в realm).
    # NB: точное имя поля для external-IdP в v0.71 — ЭМПИРИЧЕСКАЯ проверка по логам netbird-server.
    audience: "netbird"
    signKeyRefreshEnabled: true
    dashboardRedirectURIs:
      - "https://nb.${FABRIC_DOMAIN}/nb-auth"
      - "https://nb.${FABRIC_DOMAIN}/nb-silent-auth"
    cliRedirectURIs:
      - "http://localhost:53000/"

  reverseProxy:
    # Доверяем X-Forwarded от edge-Traefik. 172.30.0.0/24 — docker-сеть netbird
    # (edge подключается сюда external; единственный «прокси» в этой подсети).
    trustedHTTPProxies:
      - "172.30.0.0/24"

  store:
    engine: "sqlite"
    encryptionKey: "${DATASTORE_ENCRYPTION_KEY}"
