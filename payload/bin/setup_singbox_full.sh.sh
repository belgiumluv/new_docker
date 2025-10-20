#!/usr/bin/env bash
set -euo pipefail

# === настройки (правь при необходимости) ===========================
SING_HOME="/vpn"
SING_BIN="${SING_HOME}/sing-box"
SING_CFG="${SING_HOME}/server.json"  # твой конфиг
SERVICE_NAME="sing-box"

UNIT_DIR="/etc/systemd/system"
SERVICE_UNIT="${UNIT_DIR}/${SERVICE_NAME}.service"
RELOAD_PATH_UNIT="${UNIT_DIR}/reload.path"
RELOAD_SERVICE_UNIT="${UNIT_DIR}/reload.service"
RUN_USER="singbox"
RUN_GROUP="singbox"

# === функции =======================================================
log(){ echo "[$(date +'%F %T')] $*"; }

need_root(){
  if [ "$(id -u)" -ne 0 ]; then
    echo "Запусти скрипт от root: sudo $0" >&2
    exit 1
  fi
}

ensure_user(){
  if ! id -u "$RUN_USER" >/dev/null 2>&1; then
    log "Создаю пользователя/группу ${RUN_USER}"
    groupadd --system "$RUN_GROUP" 2>/dev/null || true
    useradd  --system --no-create-home --shell /sbin/nologin -g "$RUN_GROUP" "$RUN_USER" 2>/dev/null || true
  fi
}

check_files(){
  if [ ! -f "$SING_BIN" ]; then
    echo "Не найден бинарник: $SING_BIN" >&2
    exit 1
  fi
  if [ ! -f "$SING_CFG" ]; then
    echo "Не найден конфиг: $SING_CFG" >&2
    exit 1
  fi
}

make_exec(){
  if [ ! -x "$SING_BIN" ]; then
    log "Делаю исполняемым: $SING_BIN"
    chmod +x "$SING_BIN"
  fi
}

write_units(){
  log "Пишу unit: $SERVICE_UNIT"
  cat > "$SERVICE_UNIT" <<EOF
[Unit]
Description=sing-box service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
WorkingDirectory=${SING_HOME}

# Проверяем конфиг перед запуском
ExecStartPre=/bin/bash -lc '${SING_BIN} check -c ${SING_CFG}'

# Основной запуск
ExecStart=${SING_BIN} run -c ${SING_CFG}

# Автоперезапуск при падении
Restart=always
RestartSec=3

# Полезные лимиты/капабилити
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

# Логи в journald
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  log "Пишу unit: $RELOAD_SERVICE_UNIT"
  cat > "$RELOAD_SERVICE_UNIT" <<EOF
[Unit]
Description=Reload ${SERVICE_NAME} when ${SING_CFG} changes
StartLimitIntervalSec=60
StartLimitBurst=20

[Service]
Type=oneshot
# Дебаунс 2с, проверка валидности, затем безопасный перезапуск
ExecStart=/bin/sh -c 'sleep 2; ${SING_BIN} check -c ${SING_CFG} && systemctl restart ${SERVICE_NAME} || echo "[${SERVICE_NAME}] invalid config, skip"'
EOF

  log "Пишу unit: $RELOAD_PATH_UNIT"
  cat > "$RELOAD_PATH_UNIT" <<EOF
[Unit]
Description=Watch ${SING_CFG} for changes

[Path]
PathChanged=${SING_CFG}

[Install]
WantedBy=multi-user.target
EOF
}

set_permissions(){
  log "Выставляю владельца ${RUN_USER}:${RUN_GROUP} на ${SING_HOME} (если возможно)"
  chown -R "${RUN_USER}:${RUN_GROUP}" "${SING_HOME}" || true
}

enable_start(){
  log "Перечитываю конфигурацию systemd"
  systemctl daemon-reload

  log "Включаю и запускаю ${SERVICE_NAME}.service"
  systemctl enable --now "${SERVICE_NAME}.service"

  log "Включаю и запускаю reload.path (watcher)"
  systemctl enable --now "$(basename "$RELOAD_PATH_UNIT")"

  log "Статусы:"
  systemctl --no-pager --full status "${SERVICE_NAME}.service" || true
  systemctl --no-pager --full status "$(basename "$RELOAD_PATH_UNIT")" || true
}

# === выполнение ====================================================
need_root
ensure_user
check_files
make_exec
write_units
set_permissions
enable_start

log "Готово. Правь ${SING_CFG} — сервис сам перезапустится после валидации."
