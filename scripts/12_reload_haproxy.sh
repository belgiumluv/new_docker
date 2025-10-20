#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Hot-reload HAProxy (container/K8s safe)
# - Проверяет новый конфиг (-c)
# - Если старый процесс есть — запускает новый и передаёт -sf <oldpid>
# - Если процесса нет — стартует в фоне
# ==============================================================================

APP_ROOT="${APP_ROOT:-/app}"
APP_CFG="${APP_CFG:-$APP_ROOT/config}"
APP_DATA="${APP_DATA:-$APP_ROOT/data}"

HAP_BIN="${HAP_BIN:-haproxy}"
HAP_CFG="${HAP_CFG:-$APP_CFG/haproxy/haproxy.cfg}"
RUN_DIR="${RUN_DIR:-$APP_DATA/run}"
LOG_DIR="${LOG_DIR:-$APP_DATA/logs}"
PID_FILE="${PID_FILE:-$RUN_DIR/haproxy.pid}"

EXTRA_ARGS="${HAP_EXTRA_ARGS:-}"    # например: -db
RELOAD_GRACE="${RELOAD_GRACE:-5}"   # секунды ожидания после запуска нового мастера

mkdir -p "$RUN_DIR" "$LOG_DIR" "$(dirname "$HAP_CFG")"

get_pid() { [[ -f "$PID_FILE" ]] && cat "$PID_FILE" 2>/dev/null || true; }
is_running() { local p; p="$(get_pid)"; [[ -n "${p:-}" && -d "/proc/$p" ]]; }

start_bg() {
  echo "[run ] starting haproxy (daemon) with $HAP_CFG"
  set +e
  "$HAP_BIN" -W -f "$HAP_CFG" -p "$PID_FILE" -D $EXTRA_ARGS
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "[err ] haproxy failed to start (rc=$rc)." >&2
    exit $rc
  fi
  sleep 1
  if ! is_running; then
    echo "[err ] haproxy not running after start." >&2
    exit 2
  fi
  echo "[ok  ] started (pid=$(get_pid))"
}

# --- Проверка бинаря/конфига --------------------------------------------------
if ! command -v "$HAP_BIN" >/dev/null 2>&1; then
  echo "[err ] haproxy binary not found: $HAP_BIN" >&2
  exit 2
fi
if [[ ! -f "$HAP_CFG" ]]; then
  echo "[err ] haproxy config not found: $HAP_CFG" >&2
  exit 2
fi

echo "[check] $HAP_BIN -c -f $HAP_CFG"
"$HAP_BIN" -c -f "$HAP_CFG"

# --- Горячий перезапуск или старт --------------------------------------------
oldpid="$(get_pid || true)"
if [[ -n "${oldpid:-}" && -d "/proc/$oldpid" ]]; then
  echo "[info] hot-reload from old pid=$oldpid"
  echo "[run ] $HAP_BIN -W -f $HAP_CFG -p $PID_FILE -D -sf $oldpid $EXTRA_ARGS"
  "$HAP_BIN" -W -f "$HAP_CFG" -p "$PID_FILE" -D -sf "$oldpid" $EXTRA_ARGS

  sleep "$RELOAD_GRACE"
  if ! is_running; then
    echo "[err ] reload failed: no running pid after grace." >&2
    exit 2
  fi
  echo "[ok  ] hot-reload completed (new pid=$(get_pid))"
else
  echo "[info] no existing haproxy process, starting fresh"
  start_bg
fi
