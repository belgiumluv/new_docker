#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# HAProxy deploy for container/K8s
# - Конфиг: /app/config/haproxy/haproxy.cfg
# - Runtime: /app/data/{run,logs}
# - НИКАКОГО /etc/haproxy и systemd
# - Режимы:
#     RUN_MODE=fg     — запустить в foreground (основной процесс)
#     RUN_MODE=bg     — запустить в фоне (PID в файле)
#     RUN_MODE=watch  — следить за конфигом и hot-reload по изменению
#     RUN_MODE=skip   — не запускать (по умолчанию)
# ==============================================================================

APP_ROOT="${APP_ROOT:-/app}"
APP_CFG="${APP_CFG:-$APP_ROOT/config}"
APP_DATA="${APP_DATA:-$APP_ROOT/data}"

HAP_BIN="${HAP_BIN:-haproxy}"
HAP_CFG="${HAP_CFG:-$APP_CFG/haproxy/haproxy.cfg}"

RUN_DIR="${RUN_DIR:-$APP_DATA/run}"
LOG_DIR="${LOG_DIR:-$APP_DATA/logs}"
PID_FILE="${PID_FILE:-$RUN_DIR/haproxy.pid}"
OUT_LOG="${OUT_LOG:-$LOG_DIR/haproxy.out.log}"
ERR_LOG="${ERR_LOG:-$LOG_DIR/haproxy.err.log}"

RUN_MODE="${RUN_MODE:-skip}"       # fg | bg | watch | skip
RELOAD_GRACE="${RELOAD_GRACE:-5}"  # секунд ожидания между старым/новым
EXTRA_ARGS="${HAP_EXTRA_ARGS:-}"    # доп. флаги для haproxy (например, -db)

echo "[info] APP_ROOT=$APP_ROOT"
echo "[info] APP_CFG=$APP_CFG"
echo "[info] APP_DATA=$APP_DATA"
echo "[info] HAP_CFG=$HAP_CFG"
echo "[info] RUN_MODE=$RUN_MODE"

# --- checks -------------------------------------------------------------------
if ! command -v "$HAP_BIN" >/dev/null 2>&1; then
  echo "[err ] haproxy binary not found: $HAP_BIN" >&2
  exit 2
fi
if [[ ! -f "$HAP_CFG" ]]; then
  echo "[err ] haproxy config not found: $HAP_CFG" >&2
  exit 2
fi

mkdir -p "$RUN_DIR" "$LOG_DIR" "$(dirname "$HAP_CFG")"

# Владелец (опционально)
if [[ -n "${APP_OWNER:-}" ]]; then
  user=$(echo "$APP_OWNER" | cut -d':' -f1)
  group=$(echo "$APP_OWNER" | cut -d':' -f2)
  chown -R "$user":"$group" "$APP_DATA" || echo "[warn] chown $APP_OWNER failed (non-critical)"
fi

# Валидация конфига
echo "[run ] $HAP_BIN -c -f $HAP_CFG"
"$HAP_BIN" -c -f "$HAP_CFG"

# --- helpers ------------------------------------------------------------------
get_pid() { [[ -f "$PID_FILE" ]] && cat "$PID_FILE" 2>/dev/null || true; }
is_running() { local p; p="$(get_pid)"; [[ -n "${p:-}" && -d "/proc/$p" ]]; }

start_fg() {
  echo "[run ] exec $HAP_BIN -W -f $HAP_CFG -p $PID_FILE $EXTRA_ARGS"
  exec "$HAP_BIN" -W -f "$HAP_CFG" -p "$PID_FILE" $EXTRA_ARGS
}

start_bg() {
  echo "[run ] $HAP_BIN -W -f $HAP_CFG -p $PID_FILE -Ds $EXTRA_ARGS (logs -> files)"
  # -D (daemon) + -W (master-worker). Логи перенаправляем в файлы оболочкой.
  set +e
  "$HAP_BIN" -W -f "$HAP_CFG" -p "$PID_FILE" -D $EXTRA_ARGS >>"$OUT_LOG" 2>>"$ERR_LOG" &
  set -e
  sleep 1
  if ! is_running; then
    echo "[err ] haproxy failed to start (check logs)." >&2
    exit 2
  fi
  echo "[ok  ] haproxy started (pid=$(get_pid))"
}

reload_hot() {
  # Аккуратный hot-reload:
  #   - проверяем новый конфиг
  #   - запускаем новый master с -sf <oldpid>
  local oldpid
  oldpid="$(get_pid)"
  echo "[info] hot-reload request (oldpid=${oldpid:-none})"

  echo "[check] $HAP_BIN -c -f $HAP_CFG"
  if ! "$HAP_BIN" -c -f "$HAP_CFG"; then
    echo "[err ] new config invalid; abort reload."
    return 2
  fi

  if [[ -n "${oldpid:-}" && -d "/proc/$oldpid" ]]; then
    echo "[run ] $HAP_BIN -W -f $HAP_CFG -p $PID_FILE -D -sf $oldpid $EXTRA_ARGS"
    "$HAP_BIN" -W -f "$HAP_CFG" -p "$PID_FILE" -D -sf "$oldpid" $EXTRA_ARGS
  else
    echo "[info] no running process found; starting fresh"
    start_bg
  fi

  # подождём немного, чтобы убедиться что новый процесс живой
  sleep "$RELOAD_GRACE"
  if ! is_running; then
    echo "[err ] haproxy reload failed (no running pid)." >&2
    return 2
  fi
  echo "[ok  ] hot-reload completed (pid=$(get_pid))"
}

watch_loop() {
  echo "[info] watch mode enabled for $HAP_CFG"
  # первый запуск
  start_bg

  if command -v inotifywait >/dev/null 2>&1; then
    echo "[ok  ] using inotifywait"
    while true; do
      inotifywait -e modify,move,create,close_write "$(dirname "$HAP_CFG")" >/dev/null 2>&1 || true
      echo "[info] change detected, attempting hot-reload..."
      reload_hot || echo "[warn] hot-reload failed; keep old process"
    done
  else
    echo "[warn] inotifywait not found; using checksum polling"
    local last_sum
    last_sum="$(sha256sum "$HAP_CFG" | awk '{print $1}')"
    while true; do
      sleep 2
      local cur_sum
      cur_sum="$(sha256sum "$HAP_CFG" | awk '{print $1}')"
      if [[ "$cur_sum" != "$last_sum" ]]; then
        echo "[info] config changed, attempting hot-reload..."
        if reload_hot; then
          last_sum="$cur_sum"
        else
          echo "[warn] hot-reload failed; not updating checksum"
        fi
      fi
    done
  fi
}

# --- main ---------------------------------------------------------------------
case "${RUN_MODE,,}" in
  fg)     start_fg ;;
  bg)     start_bg ;;
  watch)  watch_loop ;;
  skip|*) echo "[info] RUN_MODE=skip — not starting haproxy" ;;
esac

echo "[done] haproxy deploy script finished"
