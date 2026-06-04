# ═════════════════════════════════════════════════════════════════════
#  Optimized Keycloak для mgmt-узла фабрики (закрепление Phase 1).
#
#  Augmentation (`kc.sh build`, ~166s на 1 CPU) выполняется ОДИН раз здесь,
#  на этапе сборки образа — а не при каждом `start`. Runtime затем поднимается
#  через `start --optimized` (~10s вместо ~3 минут). Это критично для
#  reboot-survival: после перезагрузки login лежит секунды, а не минуты.
#
#  Build-time опции ДОЛЖНЫ быть запечены здесь (KC_DB, KC_HEALTH_ENABLED).
#  Runtime-опции (KC_HOSTNAME, KC_DB_URL/креды, KC_PROXY_HEADERS, KC_HTTP_ENABLED)
#  остаются в compose-env и подставляются при запуске.
#
#  Версия пиннится через ARG (детерминированная сборка вместо :latest).
# ═════════════════════════════════════════════════════════════════════
ARG KC_VERSION=26.6.3

FROM quay.io/keycloak/keycloak:${KC_VERSION} AS builder
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:${KC_VERSION}
COPY --from=builder /opt/keycloak/ /opt/keycloak/
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
