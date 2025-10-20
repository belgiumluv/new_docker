#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/app}"
APP_DATA="${APP_DATA:-$APP_ROOT/data}"
TLS_DIR="${TLS_DIR:-$APP_ROOT/tls}"

ENABLE_CERTBOT="${ENABLE_CERTBOT:-false}"
TLS_DOMAIN="${TLS_DOMAIN:-}"
TLS_EMAIL="${TLS_EMAIL:-}"
CERTBOT_STAGING="${CERTBOT_STAGING:-false}"

echo "[info] TLS_DIR=$TLS_DIR"

mkdir -p "$TLS_DIR" "$APP_DATA"

# Если ключи уже есть — выходим спокойно
if [[ -f "$TLS_DIR/tls.crt" && -f "$TLS_DIR/tls.key" ]]; then
  echo "[ok  ] TLS certs already present in $TLS_DIR"
  exit 0
fi

# Если certbot выключен — просто предупредим и выйдем
if [[ "$ENABLE_CERTBOT" != "true" ]]; then
  echo "[err ] No TLS certs found in $TLS_DIR."
  echo "       In Kubernetes, create a Certificate with cert-manager and mount its Secret to /app/tls."
  echo "       Or set ENABLE_CERTBOT=true (not recommended) and provide TLS_DOMAIN/TLS_EMAIL."
  exit 0
fi

if [[ -z "$TLS_DOMAIN" || -z "$TLS_EMAIL" ]]; then
  echo "[err ] ENABLE_CERTBOT=true, but TLS_DOMAIN or TLS_EMAIL not set."
  exit 1
fi

echo "[info] ENABLE_CERTBOT=true — attempting to obtain certs with certbot (standalone)"

# Рабочие директории certbot внутри /app/data (записываемые non-root)
LE_CFG="$APP_DATA/letsencrypt/config"
LE_WORK="$APP_DATA/letsencrypt/work"
LE_LOGS="$APP_DATA/letsencrypt/logs"
mkdir -p "$LE_CFG" "$LE_WORK" "$LE_LOGS"

# Флаги для тестового (стейджингового) CA Let's Encrypt, чтобы не ловить лимиты
EXTRA_FLAGS=()
if [[ "$CERTBOT_STAGING" == "true" ]]; then
  EXTRA_FLAGS+=(--staging)
fi

# IMPORTANT:
# - Мы заранее вызываемся ДО запуска haproxy, поэтому порт 80 свободен.
# - capability cap_net_bind_service дан python3, так что non-root процесс сможет слушать :80.
set +e
certbot certonly --standalone \
  -d "$TLS_DOMAIN" \
  -m "$TLS_EMAIL" --agree-tos --non-interactive \
  --config-dir "$LE_CFG" --work-dir "$LE_WORK" --logs-dir "$LE_LOGS" \
  "${EXTRA_FLAGS[@]}"
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "[err ] certbot failed (rc=$rc). See logs in $LE_LOGS"
  exit $rc
fi

LIVE_DIR="$LE_CFG/live/$TLS_DOMAIN"
if [[ ! -f "$LIVE_DIR/fullchain.pem" || ! -f "$LIVE_DIR/privkey.pem" ]]; then
  echo "[err ] certbot finished but live dir not found: $LIVE_DIR"
  exit 2
fi

# Копируем в /app/tls
cp -f "$LIVE_DIR/fullchain.pem" "$TLS_DIR/tls.crt"
cp -f "$LIVE_DIR/privkey.pem"   "$TLS_DIR/tls.key"
echo "[ok  ] certs copied to $TLS_DIR (tls.crt, tls.key)"
