#!/usr/bin/env bash
set -euo pipefail

DB_DIR="/var/lib/bd"
DB_FILE="${DB_DIR}/bd.db"
DB_OWNER_USER="vpnserver"
DB_OWNER_GROUP="vpnserver"
SCHEMA_SQL=""   # при необходимости укажи путь к schema.sql (например: /opt/vpn/schema.sql)

log(){ echo "[$(date +'%F %T')] $*"; }

# 1) Установка sqlite3 (CLI) и libsqlite3 (обычно уже есть)
install_sqlite() {
  log "Устанавливаю sqlite3…"
  if command -v sqlite3 >/dev/null 2>&1; then
    log "sqlite3 уже установлен"
    return
  fi
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y sqlite3
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y sqlite
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y sqlite
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add --no-cache sqlite
  else
    echo "Неизвестный пакетный менеджер. Установи sqlite3 вручную." >&2
    exit 1
  fi
}

# 2) Создать каталог и выставить права
prep_dir() {
  log "Готовлю каталог ${DB_DIR}…"
  sudo mkdir -p "${DB_DIR}"
  sudo chown -R "${DB_OWNER_USER}:${DB_OWNER_GROUP}" "${DB_DIR}"
  sudo chmod 0750 "${DB_DIR}"
}

# 3) Создать/инициализировать БД
init_db() {
  if [ -f "${DB_FILE}" ]; then
    log "БД уже существует: ${DB_FILE}"
  else
    log "Создаю пустую БД: ${DB_FILE}"
    sudo -u "${DB_OWNER_USER}" sqlite3 "${DB_FILE}" 'PRAGMA journal_mode=WAL;'
  fi

  # Применить схему, если указана
  if [ -n "${SCHEMA_SQL}" ] && [ -f "${SCHEMA_SQL}" ]; then
    log "Применяю схему: ${SCHEMA_SQL}"
    sudo -u "${DB_OWNER_USER}" sqlite3 "${DB_FILE}" < "${SCHEMA_SQL}"
  fi

  # Права на файл БД
  sudo chown "${DB_OWNER_USER}:${DB_OWNER_GROUP}" "${DB_FILE}"
  sudo chmod 0640 "${DB_FILE}"
}

main() {
  install_sqlite
  prep_dir
  init_db
  log "Готово. БД: ${DB_FILE}"
  log "Автозапуск не требуется: SQLite — это файл. Приложение vpnserver будет открывать его напрямую."
}

main "$@"
