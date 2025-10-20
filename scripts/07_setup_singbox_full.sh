#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# sing-box setup (container/K8s safe) + auto-reload on config change
# - Конфиг /app/config/server.json
# - Runtime /app/data
# - Без /etc, systemd и пр.
# - Режимы:
#     RUN_MODE=fg     — запустить в foreground (без вотчера)
#     RUN_MODE=bg     — запустить в фоне (без вотчера)
#     RUN_MODE=watch  — запустить в фоне + следить за изменениями конфигурации и перезапускать
#     RUN_MODE=skip   — ничего не запускать (по умолчанию)
# ==============================================================================

APP_ROOT="${APP_ROOT:-/app}"
APP_CFG="${APP_CFG:-$APP_ROOT/config}"
APP_DATA="${APP_DATA:-$APP_ROOT/data}"

SINGBOX_BIN="${SINGBOX_BIN:-sing-box}"
SINGBOX_CONFIG="${SINGBOX_CONFIG:-$APP_CFG/server.json}"

RUN_DIR="${RUN_DIR:-$APP_DATA/run}"
LOG_DIR="${LOG_DIR:-$APP_DATA/logs}"
PID_FILE="${PID_FILE:-$RUN_DIR/sing-box.pid}"
OUT_LOG="${OUT_LOG:-$LOG_DIR/sing-box.out.log}"
ERR_LOG="${ERR_LOG:-$LOG_DIR/sing-box.err.log}"

RUN_MODE="${RUN_MODE:-skip}"     # fg | bg | watch | skip
RELOAD_GRACE="${RELOAD_GRACE:-5}" # секунд ожидания после SIGTERM перед перезапуском

echo "[info] APP_ROOT=$APP_ROOT"
echo "[info] APP_CFG=$APP_CFG"
echo "[info] APP_DATA=$APP_DATA"
echo "[info] SINGBOX_BIN=$SINGBOX_BIN"
echo "[info] SINGBOX_CONFIG=$SINGBOX_CONFIG"
echo "[info] RUN_MODE=$RUN_MODE"

# --- checks -------------------------------------------------------------------
if ! command -v "$SINGBOX_BIN" >/dev/null 2>&1; then
  echo "[err ] sing-box binary not found: $SINGBOX_BIN" >&2
  exit 2
fi
if [[ ! -f "$SINGBOX_CONFIG" ]]; then
  echo "[err ] sing-box config not found: $SINGBOX_CONFIG" >&2
  exit 2
fi

mkdir -p "$RUN_DIR" "$LOG_DIR"

if [[ -n "${APP_OWNER:-}" ]]; then
  user=$(echo "$APP_OWNER" | cut -d':' -f1)
  group=$(echo "$APP_OWNER" | cut -d':' -f2)
  chown -R "$user":"$group" "$APP_DATA" || echo "[warn] chown $APP_OWNER failed (non-critical)"
fi

echo "[run ] $SINGBOX_BIN check -c $SINGBOX_CONFIG"
if ! "$SINGBOX_BIN" check -c "$SINGBOX_CONFIG"; then
  echo "[err ] sing-box config validation failed." >&2
  exit 2
fi
echo "[ok  ] sing-box config is valid."

# --- helpers ------------------------------------------------------------------
get_pid() {
  [[ -f "$PID_FILE" ]] && cat "$PID_FILE" 2>/dev/null || true
}

is_running() {
  local pid
  pid="$(get_pid)"
  [[ -n "${pid:-}" && -d "/proc/$pid" ]]
}

start_bg() {
  echo "[run ] start sing-box in background"
  set +e
  "$SINGBOX_BIN" run -c "$SINGBOX_CONFIG" >>"$OUT_LOG" 2>>"$ERR_LOG" &
  local pid=$!
  set -e
  echo "$pid" > "$PID_FILE"
  echo "[ok  ] sing-box started (pid=$pid)"
}

stop_bg() {
  local pid
  pid="$(get_pid)"
  if [[ -z "${pid:-}" ]]; then
    echo "[info] no PID file, nothing to stop"
    return 0
  fi
  if ! is_running; then
    echo "[info] process not running (pid=$pid?)"
    rm -f "$PID_FILE"
    return 0
  fi
  echo "[run ] stopping sing-box pid=$pid"
  kill "$pid" || true
  # подождём graceful shutdown
  for i in $(seq 1 "$RELOAD_GRACE"); do
    if ! is_running; then break; fi
    sleep 1
  done
  if is_running; then
    echo "[warn] still running, sending SIGKILL"
    kill -9 "$pid" || true
  fi
  rm -f "$PID_FILE"
  echo "[ok  ] stopped"
}

run_watch_loop() {
  echo "[info] watch mode enabled"
  echo "[info] trying inotifywait (inotify-tools) first; fallback to checksum polling"

  # стартуем впервые
  start_bg

  if command -v inotifywait >/dev/null 2>&1; then
    echo "[ok  ] using inotifywait to watch $SINGBOX_CONFIG"
    # следим за изменениями файла (modify, move, create)
    while true; do
      inotifywait -e modify,move,create,close_write "$(dirname "$SINGBOX_CONFIG")" >/dev/null 2>&1 || true
      # проверим валидность обновлённого конфига
      echo "[info] change detected, validating new config..."
      if "$SINGBOX_BIN" check -c "$SINGBOX_CONFIG"; then
        echo "[info] config valid, reloading..."
        stop_bg
        start_bg
      else
        echo "[err ] new config invalid, skip reload (keeping old process)"
      fi
    done
  else
    echo "[warn] inotifywait not found; using checksum polling"
    local last_sum=""
    last_sum="$(sha256sum "$SINGBOX_CONFIG" | awk '{print $1}')"
    while true; do
      sleep 2
      local cur_sum
      cur_sum="$(sha256sum "$SINGBOX_CONFIG" | awk '{print $1}')"
      if [[ "$cur_sum" != "$last_sum" ]]; then
        echo "[info] config checksum changed, validating..."
        if "$SINGBOX_BIN" check -c "$SINGBOX_CONFIG"; then
          echo "[info] config
