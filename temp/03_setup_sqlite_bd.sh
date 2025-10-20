#!/usr/bin/env bash
set -euo pipefail

# Префикс для работы с ФС хоста (в compose: ROOT_PREFIX=/host)
ROOT_PREFIX="${ROOT_PREFIX:-/host}"

DB_DIR="${ROOT_PREFIX}/var/lib/bd"
DB_FILE="${DB_DIR}/bd.db"

# Владелец/группа: можно задать ИМЕНА или UID/GID через переменные окружения
DB_OWNER_USER="${DB_OWNER_USER:-root}"
DB_OWNER_GROUP="${DB_OWNER_GROUP:-root}"
DB_OWNER_UID="${DB_OWNER_UID:-}"
DB_OWNER_GID="${DB_OWNER_GID:-}"

SCHEMA_SQL="${SCHEMA_SQL:-}"   # например: ${ROOT_PREFIX}/opt/vpn/schema.sql

log(){ echo "[$(date +'%F %T')] $*"; }

_have_cmd(){ command -v "$1" >/dev/null 2>&1; }

_resolve_owner() {
  # Определяем итоговые owner/group для chown: UID/GID приоритетнее имён
  local owner group
  if [[ -n "$DB_OWNER_UID" && -n "$DB_OWNER_GID" ]]; then
    owner="${DB_OWNER_UID}:${DB_OWNER_GID}"
  else
    owner="${DB_OWNER_USER}:${DB_OWNER_GROUP}"
  fi
  echo "$owner"
}

install_sqlite() {
  # В образе уже есть sqlite3; оставим проверку на всякий случай
  log "Проверяю наличие sqlite3…"
  if _have_cmd sqlite3; then
    log "sqlite3 уже установлен"
    return
  fi
  # Если очень нужно — можно добавить установку, но обычно не требуется:
  log "sqlite3 не найден. Установи его в образ на этапе сборки."
  exit 1
}

prep_dir() {
  log "Готовлю каталог ${DB_DIR}…"
  mkdir -p "${DB_DIR}"
  chown -R "$(_resolve_owner)" "${DB_DIR}" || true
  chmod 0750 "${DB_DIR}" || true
}

init_db() {
  if [[ -f "${DB_FILE}" ]]; then
    log "БД уже существует: ${DB_FILE}"
  else
    log "Создаю пустую БД: ${DB_FILE}"
    # Гарантированно создаём файл с нужными правами
    install -m 0640 -o "$(cut -d: -f1 <<<"$(_resolve_owner)")" -g "$(cut -d: -f2 <<<"$(_resolve_owner)")" /dev/null "${DB_FILE}" 2>/dev/null || true
    # Инициализируем через sqlite3 (root), затем выставим владельца ещё раз
    sqlite3 "${DB_FILE}" 'PRAGMA journal_mode=WAL;' || {
      log "Не удалось инициализировать БД через sqlite3"; exit 1;
    }
  fi

  if [[ -n "${SCHEMA_SQL}" && -f "${SCHEMA_SQL}" ]]; then
    log "Применяю схему: ${SCHEMA_SQL}"
    sqlite3 "${DB_FILE}" < "${SCHEMA_SQL}"
  fi

  # Финальные права/владелец
  chown "$(_resolve_owner)" "${DB_FILE}" || true
  chmod 0640 "${DB_FILE}" || true
}

main() {
  install_sqlite
  prep_dir
  init_db
  log "Готово. БД: ${DB_FILE}"
  log "SQLite — это файл, отдельный сервис не требуется."
}

main "$@"