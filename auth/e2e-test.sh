#!/usr/bin/env bash
# E2E-тест forward-auth: блокировка без сессии + полный вход через Keycloak → доступ к whoami.
set -u
J=$(mktemp)
R=(--resolve kc.lab.test:8480:127.0.0.1 --resolve app.lab.test:8480:127.0.0.1 --max-time 15 -sS)

echo "=== 1) без сессии: app.lab должен НЕ пускать ==="
code=$(curl "${R[@]}" -o /dev/null -w '%{http_code}' "http://app.lab.test:8480/")
echo "   app.lab/ → HTTP $code  (ожидаем 401 — forward-auth заблокировал)"

echo "=== 2) старт OIDC: /oauth2/start → редирект на Keycloak, тянем форму логина ==="
loginpage=$(curl "${R[@]}" -c "$J" -b "$J" -L "http://app.lab.test:8480/oauth2/start?rd=%2F")
action=$(printf '%s' "$loginpage" | grep -oE 'action="[^"]+"' | head -1 | sed 's/action="//; s/"$//; s/&amp;/\&/g')
if [ -z "$action" ]; then echo "   ✗ не нашёл форму логина Keycloak"; echo "$loginpage" | head -c 300; rm -f "$J"; exit 1; fi
echo "   страница логина Keycloak получена, form action: ${action:0:70}..."

echo "=== 3) POST учётки tester/test12345 → Keycloak редиректит на callback ==="
loc=$(curl "${R[@]}" -c "$J" -b "$J" -i -X POST "$action" \
  --data-urlencode "username=tester" --data-urlencode "password=test12345" --data-urlencode "credentialId=" \
  | grep -i '^location:' | tail -1 | sed 's/[Ll]ocation: //; s/\r//')
echo "   redirect → ${loc:0:70}..."
[ -z "$loc" ] && { echo "   ✗ логин не дал редиректа (неверные креды?)"; rm -f "$J"; exit 1; }

echo "=== 4) проходим callback → сессия → повторный доступ к app.lab ==="
curl "${R[@]}" -c "$J" -b "$J" -L -o /dev/null "$loc"   # callback устанавливает сессию
echo "=== 5) с сессией: app.lab должен ПУСТИТЬ (whoami + проброс identity) ==="
out=$(curl "${R[@]}" -c "$J" -b "$J" -w '\n[HTTP %{http_code}]' "http://app.lab.test:8480/")
echo "$out" | grep -iE 'X-Auth-Request|X-Forwarded-User|Hostname|\[HTTP' | head -12
rm -f "$J"
