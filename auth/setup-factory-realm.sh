#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
#  Пересборка realm factory-admin на mgmt-узле: delete + re-import
#  корректного realms/factory-admin.json + post-import конфигурация,
#  которую нельзя/не нужно держать в публичном JSON:
#    - groups-claim client-scope (+ mapper) и назначение клиентам
#    - свап example.com → реальный домен для netbird redirectUris
#    - owner-юзер (роль factory-admin)
#
#  Идемпотентно. Запускать ИЗ каталога auth/ на узле с контейнером keycloak:
#    FABRIC_DOMAIN=victory62.org NB_OWNER_PASSWORD=... ./setup-factory-realm.sh
#  (FABRIC_DOMAIN/креды берутся из auth/.env, если не заданы в окружении)
# ═════════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] && { set -a; . ./.env; set +a; }
: "${FABRIC_DOMAIN:?FABRIC_DOMAIN не задан (env или auth/.env)}"
: "${KC_ADMIN_USER:?}"; : "${KC_ADMIN_PASSWORD:?}"
KC=keycloak
K="docker exec $KC /opt/keycloak/bin/kcadm.sh"

echo "== kcadm auth =="
$K config credentials --server http://localhost:8080 --realm master \
  --user "$KC_ADMIN_USER" --password "$KC_ADMIN_PASSWORD" >/dev/null

echo "== delete + re-import realm factory-admin =="
$K delete realms/factory-admin >/dev/null 2>&1 && echo "  старый realm удалён" || echo "  realm не существовал"
docker cp realms/factory-admin.json $KC:/tmp/factory-admin.json >/dev/null
$K create realms -f /tmp/factory-admin.json >/dev/null && echo "  realm импортирован"

echo "== стандартные client-scopes (ожидаем profile/email/roles) =="
$K get client-scopes -r factory-admin --fields name 2>/dev/null \
  | grep '"name"' | sed 's/[^a-z_-]//g' | sort | tr '\n' ' '; echo

echo "== groups-claim scope + mapper =="
cat > /tmp/gs.json <<'JSON'
{"name":"groups","description":"OIDC group membership claim для ACL","protocol":"openid-connect","attributes":{"include.in.token.scope":"true","display.on.consent.screen":"false"}}
JSON
docker cp /tmp/gs.json $KC:/tmp/gs.json >/dev/null
$K create client-scopes -r factory-admin -f /tmp/gs.json >/dev/null 2>&1 && echo "  groups scope создан" || echo "  groups scope уже есть"
GSID=$($K get client-scopes -r factory-admin --fields id,name --format csv | tr -d '"' | awk -F, '$2=="groups"{print $1}')
cat > /tmp/gm.json <<'JSON'
{"name":"groups","protocol":"openid-connect","protocolMapper":"oidc-group-membership-mapper","config":{"claim.name":"groups","full.path":"false","access.token.claim":"true","id.token.claim":"true","userinfo.token.claim":"true"}}
JSON
docker cp /tmp/gm.json $KC:/tmp/gm.json >/dev/null
$K create "client-scopes/$GSID/protocol-mappers/models" -r factory-admin -f /tmp/gm.json >/dev/null 2>&1 \
  && echo "  groups mapper создан" || echo "  groups mapper уже есть"

echo "== назначить groups как default клиентам =="
for c in netbird grafana forward-auth-admin proxmox-msk proxmox-rzn; do
  CID=$($K get clients -r factory-admin -q clientId="$c" --fields id --format csv | tr -d '"')
  [ -n "$CID" ] && $K update "clients/$CID/default-client-scopes/$GSID" -r factory-admin >/dev/null 2>&1 \
    && echo "  groups → $c"
done

echo "== свап example.com → $FABRIC_DOMAIN (netbird redirectUris/webOrigins) =="
NBID=$($K get clients -r factory-admin -q clientId=netbird --fields id --format csv | tr -d '"')
$K update "clients/$NBID" -r factory-admin \
  -s "redirectUris=[\"https://nb.$FABRIC_DOMAIN/*\",\"http://localhost:53000\"]" \
  -s "webOrigins=[\"https://nb.$FABRIC_DOMAIN\",\"+\"]" >/dev/null \
  && echo "  netbird → nb.$FABRIC_DOMAIN"

echo "== owner-юзер nick4man =="
NBUID=$($K get users -r factory-admin -q username=nick4man --fields id --format csv | tr -d '"')
if [ -z "$NBUID" ]; then
  $K create users -r factory-admin -s username=nick4man -s enabled=true -s emailVerified=true \
    -s email="${NB_OWNER_EMAIL:-nick4man@$FABRIC_DOMAIN}" -s firstName=Nick >/dev/null
  echo "  nick4man создан"
else
  $K update "users/$NBUID" -r factory-admin -s emailVerified=true -s 'requiredActions=[]' >/dev/null
  echo "  nick4man обновлён"
fi
$K add-roles -r factory-admin --uusername nick4man --rolename factory-admin >/dev/null 2>&1 \
  && echo "  роль factory-admin → nick4man" || true
PW="${NB_OWNER_PASSWORD:-Owner!$(openssl rand -hex 5)}"
$K set-password -r factory-admin --username nick4man --new-password "$PW" >/dev/null
echo "  ПАРОЛЬ nick4man: $PW"
echo "== готово: realm factory-admin пересобран =="
