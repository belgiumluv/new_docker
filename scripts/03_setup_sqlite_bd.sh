#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Создание и инициализация SQLite базы данных
# Работает только внутри контейнера (/app/data/bd/bd.db)
# =========================================================

APP_ROOT="${APP_ROOT:-/app}"
APP_DATA="${APP_DATA:-$APP_ROOT/data}"
DB_DIR="${DB_DIR:-$APP_DATA/bd}"
DB_PATH="${SQLITE_PATH:-$DB_DIR/bd.db}"

echo "[info] APP_ROOT=$APP_ROOT"
echo "[info] APP_DATA=$APP_DATA"
echo "[info] DB_PATH=$DB_PATH"

# Создаём каталог, если отсутствует
mkdir -p "$DB_DIR"

# Проверяем, есть ли уже база
if [[ -f "$DB_PATH" ]]; then
  echo "[skip] Database already exists: $DB_PATH"
  exit 0
fi

# Создаём пустую SQLite базу
sqlite3 "$DB_PATH" "VACUUM;"
echo "[ok] SQLite database created at $DB_PATH"

# Проверяем целостность
sqlite3 "$DB_PATH" "PRAGMA integrity_check;" >/dev/null
echo "[ok] Integrity check passed"

# Устанавливаем владельца, если указано
if [[ -n "${DB_OWNER:-}" ]]; then
  user=$(echo "$DB_OWNER" | cut -d':' -f1)
  group=$(echo "$DB_OWNER" | cut -d':' -f2)
  echo "[info] chown $DB_OWNER $DB_PATH"
  chown "$user":"$group" "$DB_PATH" || echo "[warn] chown failed (non-critical)"
fi

echo "[done] SQLite setup completed"
