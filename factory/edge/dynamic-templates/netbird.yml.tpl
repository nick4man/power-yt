# Рендерится render.sh (envsubst ${FABRIC_DOMAIN}) → ../dynamic/netbird.yml.
# Реальный домен — только в dynamic/ (gitignored), в git лишь template.
#
# NetBird combined (v0.71): один backend netbird-server:80, но ДВА service-определения —
#   netbird-server      (обычный HTTP/1.1: relay-WS, REST /api, /oauth2, dashboard-auth)
#   netbird-server-h2c  (HTTP/2 cleartext для gRPC: management + signal)
# Dashboard — catch-all с priority=1 (ниже backend/grpc с priority=100).
# Edge ходит в netbird-server/nb-dashboard по имени через external-сеть `netbird`.
http:
  routers:
    netbird-grpc:
      rule: "Host(`nb.${FABRIC_DOMAIN}`) && (PathPrefix(`/signalexchange.SignalExchange/`) || PathPrefix(`/management.ManagementService/`) || PathPrefix(`/management.ProxyService/`))"
      entryPoints: [websecure]
      service: netbird-server-h2c
      priority: 100
      tls:
        certResolver: cloudflare
        domains:
          - main: "nb.${FABRIC_DOMAIN}"

    netbird-backend:
      rule: "Host(`nb.${FABRIC_DOMAIN}`) && (PathPrefix(`/relay`) || PathPrefix(`/ws-proxy/`) || PathPrefix(`/api`) || PathPrefix(`/oauth2`))"
      entryPoints: [websecure]
      service: netbird-server
      priority: 100
      tls:
        certResolver: cloudflare

    netbird-dashboard:
      rule: "Host(`nb.${FABRIC_DOMAIN}`)"
      entryPoints: [websecure]
      service: netbird-dashboard
      priority: 1
      tls:
        certResolver: cloudflare

  services:
    netbird-server:
      loadBalancer:
        passHostHeader: true
        servers:
          - url: "http://netbird-server:80"
    netbird-server-h2c:
      loadBalancer:
        passHostHeader: true
        servers:
          - url: "h2c://netbird-server:80"
    netbird-dashboard:
      loadBalancer:
        passHostHeader: true
        servers:
          - url: "http://nb-dashboard:80"
