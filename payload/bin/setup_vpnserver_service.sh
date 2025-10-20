#!/usr/bin/env bash
set -euo pipefail

BIN="/opt/vpnserver"                 # путь к бинарю
WORKDIR="/opt"                       # рабочая директория (поправь при необходимости)
USER_NAME="vpnserver"
GROUP_NAME="vpnserver"
UNIT="/etc/systemd/system/vpnserver.service"

# Проверки
if ! command -v systemctl >/dev/null 2>&1; then
  echo "Нужен systemd (systemctl не найден)." >&2; exit 1
fi
if [ ! -f "$BIN" ]; then
  echo "Не найден бинарь: $BIN" >&2; exit 1
fi

# Права на бинарь
if [ ! -x "$BIN" ]; then
  chmod +x "$BIN"
fi

# Служебный пользователь
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  groupadd --system "$GROUP_NAME" || true
  useradd  --system --no-create-home --shell /sbin/nologin -g "$GROUP_NAME" "$USER_NAME" || true
fi

# Владельцы (не обязательно; закомментируй, если не нужно)
chown "$USER_NAME:$GROUP_NAME" "$BIN" || true

# Unit-файл
cat > "$UNIT" <<EOF
[Unit]
Description=VPN Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
Group=${GROUP_NAME}
WorkingDirectory=${WORKDIR}

# Если нужны переменные/аргументы — добавь здесь Environment=... и аргументы к ExecStart
ExecStart=${BIN}

# Автоперезапуск при падении
Restart=always
RestartSec=3

# Полезные лимиты/права для портов <1024 (оставь, если слушаешь 80/443 и т.п.)
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Активируем
systemctl daemon-reload
systemctl enable --now vpnserver

# Показать статус
systemctl --no-pager --full status vpnserver || true
echo "Готово: сервис vpnserver запущен и включён в автозапуск."
