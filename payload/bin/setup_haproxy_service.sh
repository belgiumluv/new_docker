#!/usr/bin/env bash
set -euo pipefail

HAP_HOME="/opt/haproxy"
HAP_BIN="$HAP_HOME/sbin/haproxy"
HAP_CFG="$HAP_HOME/haproxy.cfg"
UNIT_PATH="/etc/systemd/system/haproxy.service"

# --- проверки ---------------------------------------------------------------
if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemd/systemctl не найден. Этот скрипт требует systemd." >&2
  exit 1
fi
if [ ! -x "$HAP_BIN" ]; then
  echo "[*] Делаю бинарь исполняемым: $HAP_BIN"
  chmod +x "$HAP_BIN"
fi
if [ ! -f "$HAP_CFG" ]; then
  echo "Конфиг не найден: $HAP_CFG" >&2
  exit 1
fi

# --- пользователь/группа (необязательно, но безопаснее) --------------------
if ! id -u haproxy >/dev/null 2>&1; then
  echo "[*] Создаю пользователя/группу haproxy"
  groupadd --system haproxy || true
  useradd  --system --no-create-home --shell /sbin/nologin -g haproxy haproxy || true
fi

# --- systemd unit -----------------------------------------------------------
echo "[*] Пишу unit-файл: $UNIT_PATH"
cat > "$UNIT_PATH" <<'EOF'
[Unit]
Description=HAProxy Load Balancer
After=network-online.target
Wants=network-online.target

[Service]
# Запуск от непривилегированного пользователя
User=haproxy
Group=haproxy

# systemd сам создаст /run/haproxy и отдаст права
RuntimeDirectory=haproxy
RuntimeDirectoryMode=0755

# Ограничения/права для портов <1024
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=100000

# Укажи пути к бинарю и конфигу через Environment
Environment=HAP_BIN=/opt/haproxy/sbin/haproxy
Environment=HAP_CFG=/opt/haproxy/haproxy.cfg
Environment=HAP_PID=/run/haproxy/haproxy.pid

# Master-Worker режим (-Ws) для корректной интеграции с systemd
ExecStart=${HAP_BIN} -Ws -f ${HAP_CFG} -p ${HAP_PID}
# Грейсфул релоад без даунтайма
ExecReload=${HAP_BIN} -Ws -f ${HAP_CFG} -p ${HAP_PID} -sf $MAINPID

# Перезапуски при падении
Restart=always
RestartSec=2

# Журнал в journald
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- права и владельцы ------------------------------------------------------
echo "[*] Выдаю владельца на конфиги/директорию (по возможности)"
chown -R haproxy:haproxy "$HAP_HOME" || true

# --- перезагрузка systemd и старт -------------------------------------------
echo "[*] Перезагружаю конфигурацию systemd"
systemctl daemon-reload

echo "[*] Включаю автозапуск и стартую сервис"
systemctl enable --now haproxy

echo "[*] Статус:"
systemctl --no-pager --full status haproxy || true

echo "[+] Готово: HAProxy запущен и будет стартовать при загрузке, с авто-перезапуском."
