# Рендерится render.sh (envsubst ${FABRIC_DOMAIN}) → dashboard.env (gitignored).
# OIDC dashboard NetBird — ВСТРОЕННЫЙ Dex IdP (combined-контейнер не умеет внешний
# Keycloak, netbird issue #5335). client/audience netbird-dashboard, issuer /oauth2.
NETBIRD_MGMT_API_ENDPOINT=https://nb.${FABRIC_DOMAIN}
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://nb.${FABRIC_DOMAIN}
AUTH_AUDIENCE=netbird-dashboard
AUTH_CLIENT_ID=netbird-dashboard
AUTH_CLIENT_SECRET=
AUTH_AUTHORITY=https://nb.${FABRIC_DOMAIN}/oauth2
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=openid profile email
AUTH_REDIRECT_URI=/nb-auth
AUTH_SILENT_REDIRECT_URI=/nb-silent-auth
NGINX_SSL_PORT=443
# TLS терминирует edge-Traefik (DNS-01), dashboard сам сертификат не получает.
LETSENCRYPT_DOMAIN=none
