#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Применяет map.yml к payload внутри контейнера.
# Ничего не пишет за пределы /app.
# =========================================================

APP_ROOT="${APP_ROOT:-/app}"
APP_CFG="${APP_CFG:-$APP_ROOT/config}"
APP_DATA="${APP_DATA:-$APP_ROOT/data}"

# Пути по умолчанию
MAP_PATH="${MAP_PATH:-$APP_CFG/map.yml}"
PAYLOAD_DIR="${PAYLOAD_DIR:-$APP_ROOT/payload}"
DEST_ROOT="${DEST_ROOT:-$APP_ROOT}"

# Режим "сухого" прогона (любой из значений true/1/yes включает dry-run)
DRY="${DRY_RUN:-false}"
DRY_FLAG=""
case "${DRY,,}" in
  true|1|yes) DRY_FLAG="--dry" ;;
esac

echo "[info] APP_ROOT=$APP_ROOT"
echo "[info] APP_CFG=$APP_CFG"
echo "[info] APP_DATA=$APP_DATA"
echo "[info] MAP_PATH=$MAP_PATH"
echo "[info] PAYLOAD_DIR=$PAYLOAD_DIR"
echo "[info] DEST_ROOT=$DEST_ROOT"
echo "[info] DRY_RUN=$DRY"

# Проверки
if [[ ! -f "$MAP_PATH" ]]; then
  echo "[err ] map.yml not found: $MAP_PATH" >&2
  exit 2
fi
if [[ ! -d "$PAYLOAD_DIR" ]]; then
  echo "[err ] payload directory not found: $PAYLOAD_DIR" >&2
  exit 2
fi

# Применяем правила копирования
PY="${PYTHON_BIN:-python3}"
COPY_SCRIPT="${COPY_SCRIPT:-$APP_ROOT/bin/copy_files.py}"

if [[ ! -f "$COPY_SCRIPT" ]]; then
  echo "[err ] copy_files.py not found: $COPY_SCRIPT" >&2
  exit 2
fi

echo "[run ] $PY $COPY_SCRIPT --map \"$MAP_PATH\" --payload \"$PAYLOAD_DIR\" --root \"$DEST_ROOT\" $DRY_FLAG"
$PY "$COPY_SCRIPT" --map "$MAP_PATH" --payload "$PAYLOAD_DIR" --root "$DEST_ROOT" $DRY_FLAG

echo "[done] map applied"
