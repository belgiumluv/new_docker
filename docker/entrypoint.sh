#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Unified entrypoint (writable configs with optional RO seed)
# - APP_CFG_RO (read-only seed, например ConfigMap в K8s)
# - APP_CFG (writable, например PVC/emptyDir) — тут живут рабочие конфиги
# - При первом старте копируем из RO в writable, если файла нет
# - Дальше все сервисы смотрят на APP_CFG (writable)
# ==============================================================================

# ---- Базовые ENV -------------------------------------------------------------
export APP_ROOT="${APP_ROOT:-/app}"
export APP_CFG="${APP_CFG:-$APP_ROOT/config}"          # writable
export APP_CFG_RO="${APP_CFG_RO:-$APP_ROOT/config.ro}" # read-only seed (может отсутствовать)
export APP_DATA="${APP_DATA:-$APP_ROOT/data}"
export SQLITE_PATH="${SQLITE_PATH:-$APP_DATA/bd/bd.db}"
export TLS_DIR="${TLS_DIR:-$APP_ROOT/tls}"

export PATH="$APP_ROOT/bin:$PATH"

echo "[info] APP_ROOT=$APP_ROOT"
echo "[info] APP_CFG=$APP_CFG (writable)"
echo "[info] APP_CFG_RO=$APP_CFG_RO (seed, read-only if mounted)"
echo "[info] APP_DATA=$APP_DATA"
echo "[info] SQLITE_PATH=$SQLITE_PATH"
echo "[info] TLS_DIR=$TLS_DIR"

# ---- Каталоги ---------------------------------------------------------------
mkdir -p "$APP_ROOT" "$APP_CFG" "$APP_DATA" "$TLS_DIR" \
         "$APP_DATA/logs" "$APP_DATA/run"

# ---- Если есть read-only seed (APP_CFG_RO) — скопируем недостающие файлы ----
if [[ -d "$APP_CFG_RO" ]]; then
  echo "[seed] found APP_CFG_RO=$APP_CFG_RO -> syncing missing files into APP_CFG=$APP_CFG"
  # Копируем ТОЛЬКО те файлы, которых нет в writable каталоге
  while IFS= read -r -d '' src; do
    rel="${src#"$APP_CFG_RO/"}"
    dst="$APP_CFG/$rel"
    if [[ ! -e "$dst" ]]; then
      mkdir -p "$(dirname "$dst")"
      cp -a "$src" "$dst"
      echo "[seed] + $rel"
    fi
  done < <(find "$APP_CFG_RO" -mindepth 1 -maxdepth 999 -print0)
else
  echo "[seed] APP_CFG_RO not present (skipping seed step)"
fi

# ---- 1) Исполняемые бины -----------------------------------------------------
if [[ -x "$APP_ROOT/bin/01_make_bin_executable.sh" ]]; then
  "$APP_ROOT/bin/01_make_bin_executable.sh"
else
  echo "[warn] 01_make_bin_executable.sh not found or not executable"
fi

# ---- 2) SQLite init ----------------------------------------------------------
if [[ -x "$APP_ROOT/bin/03_setup_sqlite_bd.sh" ]]; then
  "$APP_ROOT/bin/03_setup_sqlite_bd.sh"
else
  echo "[warn] 03_setup_sqlite_bd.sh not found or not executable"
fi

# ---- 3) server_configuration / domain.txt -----------------------------------
if [[ -x "$APP_ROOT/bin/04_setconfiguration.py" ]]; then
  python3 "$APP_ROOT/bin/04_setconfiguration.py" || {
    echo "[warn] 04_setconfiguration.py failed (check serverlist.json / public IP). Continuing..."
  }
fi

# ---- 4) Мутация server.json и haproxy путей ---------------------------------
if [[ -x "$APP_ROOT/bin/10_mutate_server_json.py" ]]; then
  python3 "$APP_ROOT/bin/10_mutate_server_json.py" || {
    echo "[warn] 10_mutate_server_json.py failed. Continuing..."
  }
fi

if [[ -x "$APP_ROOT/bin/11_apply_haproxy_changes.py" ]]; then
  python3 "$APP_ROOT/bin/11_apply_haproxy_changes.py" || {
    echo "[warn] 11_apply_haproxy_changes.py failed. Continuing..."
  }
fi

# ---- 5) TLS (в K8s монтируем Secret в /app/tls) ------------------------------
if [[ -x "$APP_ROOT/bin/06_install_certbot_renew.sh" ]]; then
  "$APP_ROOT/bin/06_install_certbot_renew.sh" || {
    echo "[warn] TLS not present yet. If running in K8s, mount Secret to $TLS_DIR"
  }
fi

# ---- 6) Supervisor-конфиг ----------------------------------------------------
if [[ -x "$APP_ROOT/bin/09_setup_vpnserver_service.sh" ]]; then
  "$APP_ROOT/bin/09_setup_vpnserver_service.sh"
else
  echo "[warn] 09_setup_vpnserver_service.sh not found or not executable"
fi

SUPERVISORD_BIN="${SUPERVISORD_BIN:-/usr/bin/supervisord}"
SUPERVISOR_CONF="${SUPERVISOR_CONF:-$APP_CFG/supervisord.conf}"

# ---- 7) Запуск supervisor как PID1 ------------------------------------------
if [[ -x "$SUPERVISORD_BIN" && -f "$SUPERVISOR_CONF" ]]; then
  echo "[run ] exec $SUPERVISORD_BIN -c $SUPERVISOR_CONF"
  exec "$SUPERVISORD_BIN" -c "$SUPERVISOR_CONF"
else
  echo "[err ] supervisord not available or config missing."
  echo "       Expected binary: $SUPERVISORD_BIN"
  echo "       Expected conf  : $SUPERVISOR_CONF"
  echo "Fallback: starting watch scripts."

  if [[ -x "$APP_ROOT/bin/07_setup_singbox_full.sh" ]]; then
    RUN_MODE=watch "$APP_ROOT/bin/07_setup_singbox_full.sh" &
  fi
  if [[ -x "$APP_ROOT/bin/08_deploy_haproxy_etc.sh" ]]; then
    RUN_MODE=watch "$APP_ROOT/bin/08_deploy_haproxy_etc.sh" &
  fi

  tail -f "$APP_DATA/logs/"*.log /dev/null 2>/dev/null || sleep infinity
fi
