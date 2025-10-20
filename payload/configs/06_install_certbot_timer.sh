#!/usr/bin/env bash
set -Eeuo pipefail

# === Что делает ===
# 1) На ХОСТЕ ставит certbot (если не установлен).
# 2) На ХОСТЕ запрашивает сертификат Let's Encrypt (standalone, порт 80 должен быть свободен).
# 3) Копирует fullchain/privkey в /opt/ssl/sert.crt и /opt/ssl/sert.key,
#    и собирает PEM /opt/ssl/sert.crt.key (ключ + цепочка).
# 4) НИКАК не трогает HAProxy и systemd. Только получение и копирование.

# === Как задать домен и почту ===
# через переменные окружения или параметрами: 12_get_cert_once.sh my.domain email@domain

# [ДОБАВЛЕНО] пробуем взять домен из /opt/domain.txt (первая непустая строка)
DOMAIN_FILE_CONTENT="$(awk 'NF{print; exit}' /vpn/domain.txt 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

DOMAIN="${1:-${CERT_DOMAIN:-${DOMAIN_FILE_CONTENT:-domainemptest.duckdns.org}}}"
EMAIL="${2:-${CERT_EMAIL:-zastawa777@gmail.com}}"

# Работать будем на ХОСТЕ через nsenter
need_nsenter(){ command -v nsenter >/dev/null 2>&1 || { echo "nsenter не найден в образе"; exit 1; }; }
host(){ nsenter -t 1 -m -u -i -n -p -- "$@"; }
host_sh(){ host /bin/sh -lc "$*"; }

log(){ echo "[$(date +'%F %T')] $*"; }

main(){
  need_nsenter
  [ -n "$DOMAIN" ] || { echo "Не задан DOMAIN"; exit 2; }

  # 0) Проверка занятости 80/tcp (только информируем, НЕ останавливаем сервисы)
  if host_sh "ss -lnt '( sport = :80 )' | awk 'NR>1{print; exit 0} END{exit 1}'"; then
    log "[WARN] Порт 80 занят на хосте. certbot --standalone может не пройти."
    log "      Освободи 80/tcp или используй другой челлендж (webroot/dns)."
  fi

  # 1) Установим certbot на ХОСТЕ при необходимости
  if ! host_sh 'command -v certbot >/dev/null 2>&1'; then
    log "[*] Устанавливаю certbot на хосте…"
    if   host_sh 'command -v apt-get >/dev/null 2>&1'; then host_sh 'apt-get update -y && apt-get install -y certbot'
    elif host_sh 'command -v dnf >/dev/null 2>&1';     then host_sh 'dnf install -y certbot'
    elif host_sh 'command -v yum >/dev/null 2>&1';     then host_sh 'yum install -y certbot'
    else
      echo "[FATAL] Не удалось установить certbot (неизвестный пакетный менеджер на хосте)"; exit 1
    fi
  fi

  # 2) Получаем/обновляем сертификат (standalone). НИКАКИХ взаимодействий с HAProxy.
  if host test -d "/etc/letsencrypt/live/${DOMAIN}"; then
    log "[*] Каталог live/${DOMAIN} уже есть — сертификат ранее получен. Перекладываю файлы."
  else
    log "[*] Запрашиваю новый сертификат для ${DOMAIN} (standalone)…"
    host certbot certonly --standalone -d "${DOMAIN}" \
      --non-interactive --agree-tos -m "${EMAIL}" --keep-until-expiring
  fi

  # 3) Перекладываем файлы в /opt/ssl с фиксированными именами sert.*
  SRC_DIR="/etc/letsencrypt/live/${DOMAIN}"
  FULLCHAIN="${SRC_DIR}/fullchain.pem"
  PRIVKEY="${SRC_DIR}/privkey.pem"

  host test -f "$FULLCHAIN" || { echo "[FATAL] Не найден $FULLCHAIN"; exit 1; }
  host test -f "$PRIVKEY"   || { echo "[FATAL] Не найден $PRIVKEY";   exit 1; }

  TARGET_DIR="/opt/ssl"
  CRT="${TARGET_DIR}/sert.crt"
  KEY="${TARGET_DIR}/sert.key"
  PEM="${TARGET_DIR}/sert.crt.key"

  # Если есть группа haproxy — используем её, иначе root
  GROUP="haproxy"; host_sh "getent group haproxy >/dev/null" || GROUP="root"

  log "[*] Копирую сертификаты в ${TARGET_DIR} (группа: ${GROUP})…"
  host mkdir -p "$TARGET_DIR"
  host install -m 0640 -o root -g "$GROUP" "$FULLCHAIN" "$CRT"
  host install -m 0640 -o root -g "$GROUP" "$PRIVKEY"   "$KEY"
  host sh -lc "cat '$KEY' '$CRT' > '$PEM' && chown root:'$GROUP' '$PEM' && chmod 0640 '$PEM'"

  # Доступ в каталог, если группа haproxy существует
  if [ "$GROUP" = "haproxy" ]; then
    host chgrp haproxy "$TARGET_DIR" 2>/dev/null || true
    host chmod 0750 "$TARGET_DIR"    2>/dev/null || true
    host chmod g+x /opt             2>/dev/null || true
  fi

  log "[OK] Готово."
  host ls -l "$TARGET_DIR"
  echo "Используй в haproxy.cfg: crt /opt/ssl/sert.crt.key"
}

main "$@"
