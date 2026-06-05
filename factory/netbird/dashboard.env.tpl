# Рендерится render.sh (envsubst ${FABRIC_DOMAIN}) → dashboard.env (gitignored).
# OIDC dashboard NetBird — внешний Keycloak realm factory-admin, публичный client netbird.
NETBIRD_MGMT_API_ENDPOINT=https://nb.${FABRIC_DOMAIN}
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://nb.${FABRIC_DOMAIN}
# OIDC — Keycloak (НЕ встроенный Dex). Публичный client → без secret, PKCE.
AUTH_AUDIENCE=netbird
AUTH_CLIENT_ID=netbird
AUTH_CLIENT_SECRET=
AUTH_AUTHORITY=https://login.${FABRIC_DOMAIN}/realms/factory-admin
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=openid profile email groups
AUTH_REDIRECT_URI=/nb-auth
AUTH_SILENT_REDIRECT_URI=/nb-silent-auth
NGINX_SSL_PORT=443
# TLS терминирует edge-Traefik (DNS-01), dashboard сам сертификат не получает.
LETSENCRYPT_DOMAIN=none
