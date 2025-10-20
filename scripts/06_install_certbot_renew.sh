#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# Сертификаты в Kubernetes:
#  - РЕКОМЕНДАЦИЯ: использовать cert-manager (Issuer/ClusterIssuer + Certificate),
#    а в контейнер монтировать Secret с ключом/цепочкой в /app/tls.
#  - По умолчанию этот скрипт ТОЛЬКО проверяет наличие сертификатов.
#  - Опционально можно включить certbot внутри контейнера
#    (ENABLE_CERTBOT=true), но это НЕ рекомендуется для K8s.
# =====================================================================

APP_ROOT="${APP_ROOT:-/app}"
APP_DATA="${APP_DATA:-$APP_ROOT/data}"
TLS_DIR="${TLS_DIR:-$APP_ROOT/tls}"

# Файлы сертификатов (как у секретов cert-manager: tls.crt/tls.key)
TLS_CERT_FILE="${TLS_CERT_FILE:-$TLS_DIR/tls.crt}"
TLS_KEY_FILE="${TLS_KEY_FILE:-$TLS_DIR/tls.key}"

# Альтернативные имена (если используешь layout как у nginx/letsencrypt)
FULLCHAIN_FILE="${FULLCHAIN_FILE:-$TLS_DIR/fullchain.pem}"
PRIVKEY_FILE="${PRIVKEY_FILE:-$TLS_DIR/privkey.pem}"

# Домен и email для certbot (если его всё-таки включать)
TLS_DOMAIN="${TLS_DOMAIN:-}"
TLS_EMAIL="${TLS_EMAIL:-admin@example.com}"

# Флаг включения certbot-процедуры (НЕ рекомендуется в K8s)
ENABLE_CERTBOT="${ENABLE_CERTBOT:-false}"

echo "[info] TLS_DIR=$TLS_DIR"
mkdir -p "$TLS_DIR"

exists_any_cert() {
  # Проверяем оба набора имён файлов
  if [[ -s "$TLS_CERT_FILE" && -s "$TLS_KEY_FILE" ]]; then
    echo "[ok] Found mounted cert-manager style certs: $TLS_CERT_FILE, $TLS_KEY_FILE"
    return 0
  fi
  if [[ -s "$FULLCHAIN_FILE" && -s "$PRIVKEY_FILE" ]]; then
    echo "[ok] Found mounted letsencrypt-style certs: $FULLCHAIN_FILE, $PRIVKEY_FILE"
    return 0
  fi
  return 1
}

copy_lets_to_tlscrt() {
  # Если есть fullchain/privkey — сделаем совместимые tls.crt/tls.key
  if [[ -s "$FULLCHAIN_FILE" && -s "$PRIVKEY_FILE" ]]; then
    echo "[info] Linking/converting fullchain/privkey -> tls.crt/tls.key"
    cp -f "$FULLCHAIN_FILE" "$TLS_CERT_FILE"
    cp -f "$PRIVKEY_FILE"   "$TLS_KEY_FILE"
  fi
}

run_certbot_once() {
  # ВНИМАНИЕ: для работы нужен certbot в образе и свободный порт 80 (standalone)
  if ! command -v certbot >/dev/null 2>&1; then
    echo "[err ] certbot not found in container. Install it in the image or use cert-manager."
    return 2
  fi
  if [[ -z "$TLS_DOMAIN" ]]; then
    echo "[err ] TLS_DOMAIN is empty. Set TLS_DOMAIN or mount certs via Secret."
    return 2
  fi

  echo "[run ] certbot certonly --standalone -d $TLS_DOMAIN"
  certbot certonly \
    --standalone \
    --preferred-challenges http \
    --agree-tos \
    --non-interactive \
    -m "$TLS_EMAIL" \
    -d "$TLS_DOMAIN"

  # Попробуем найти выданные файлы и скопировать их в $TLS_DIR
  local live_dir="/etc/letsencrypt/live/$TLS_DOMAIN"
  if [[ -d "$live_dir" ]]; then
    cp -f "$live_dir/fullchain.pem" "$FULLCHAIN_FILE"
    cp -f "$live_dir/privkey.pem"   "$PRIVKEY_FILE"
    copy_lets_to_tlscrt
    echo "[ok] Certificates acquired and placed to $TLS_DIR"
  else
    echo "[err ] certbot finished but live dir not found: $live_dir"
    return 2
  fi
}

renew_certbot_if_needed() {
  if ! command -v certbot >/dev/null 2>&1; then
    echo "[warn] certbot not found; skip renew. Prefer cert-manager in K8s."
    return 0
  fi
  echo "[run ] certbot renew --non-interactive --no-random-sleep-on-renew"
  certbot renew --non-interactive --no-random-sleep-on-renew || true

  # После renew обновим файлы в $TLS_DIR, если они в letsencrypt layout
  copy_lets_to_tlscrt
}

# --------------------------
# Основной поток выполнения
# --------------------------
if exists_any_cert; then
  # Если есть fullchain/privkey, скопируем их в tls.crt/tls.key для унификации.
  copy_lets_to_tlscrt
  echo "[done] Certificates already present. Nothing to install."
  exit 0
fi

if [[ "${ENABLE_CERTBOT,,}" == "true" ]]; then
  echo "[info] ENABLE_CERTBOT=true — attempting to obtain certs with certbot (not recommended for K8s)"
  run_certbot_once || {
    echo "[err ] certbot flow failed."
    exit 2
  }
  renew_certbot_if_needed
  echo "[done] certbot flow completed"
  exit 0
fi

# Если сюда дошли — ни сертификатов, ни certbot не используем.
# В Kubernetes правильный путь — смонтировать Secret от cert-manager.
echo "[err ] No TLS certs found in $TLS_DIR."
echo "       In Kubernetes, create a Certificate with cert-manager and mount its Secret to $TLS_DIR."
echo "       Or set ENABLE_CERTBOT=true (not recommended) and provide TLS_DOMAIN/TLS_EMAIL."
exit 2
