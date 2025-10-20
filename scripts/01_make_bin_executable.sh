#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Делает исполняемыми скрипты в /app/bin
# Ничего не трогает вне контейнерного каталога /app.
# =========================================================

APP_ROOT="${APP_ROOT:-/app}"
BIN_DIR="${BIN_DIR:-$APP_ROOT/bin}"

echo "[info] APP_ROOT=$APP_ROOT"
echo "[info] BIN_DIR=$BIN_DIR"

if [[ ! -d "$BIN_DIR" ]]; then
  echo "[err ] bin directory not found: $BIN_DIR" >&2
  exit 2
fi

# Списки расширений, которые считаем "исполняемыми"
shopt -s nullglob
EXEC_FILES=(
  "$BIN_DIR"/*.sh
  "$BIN_DIR"/*.py
  "$BIN_DIR"/*.bash
)

changed=0
for f in "${EXEC_FILES[@]}"; do
  # пропускаем директории на всякий случай
  [[ -d "$f" ]] && continue
  # добавляем исполняемый бит только владельцу
  if [[ ! -x "$f" ]]; then
    chmod u+x "$f"
    echo "[exec] +x $f"
    changed=$((changed+1))
  else
    echo "[skip] already executable: $f"
  fi
done

echo "[done] marked $changed file(s) as executable"
