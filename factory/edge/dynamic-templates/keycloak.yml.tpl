# Рендерится render.sh (envsubst) → ../dynamic/keycloak.yml на сервере.
# Реальный домен подставляется из .env (FABRIC_DOMAIN) — в git только template.
http:
  routers:
    keycloak:
      rule: "Host(`login.${FABRIC_DOMAIN}`)"
      entryPoints: [websecure]
      service: keycloak
      tls:
        certResolver: cloudflare
        domains:
          - main: "login.${FABRIC_DOMAIN}"

  services:
    keycloak:
      loadBalancer:
        passHostHeader: true
        servers:
          - url: "http://keycloak:8080"
