#!/usr/bin/env bash
set -euo pipefail

PREFIX="/opt/haproxy"
CONF="$PREFIX/haproxy.cfg"
VERSION="2.8.5"   # можно поменять на актуальную

echo "[*] Устанавливаю зависимости..."
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y build-essential libssl-dev libpcre3-dev zlib1g-dev wget
elif command -v yum >/dev/null 2>&1; then
  sudo yum groupinstall -y "Development Tools"
  sudo yum install -y pcre-devel zlib-devel openssl-devel wget
else
  echo "Неизвестный пакетный менеджер. Установи зависимости вручную."
  exit 1
fi

mkdir -p "$PREFIX"
cd "$PREFIX"

if [ ! -f "haproxy-$VERSION.tar.gz" ]; then
  echo "[*] Скачиваю HAProxy $VERSION..."
  wget https://www.haproxy.org/download/2.9/src/haproxy-$VERSION.tar.gz
fi

if [ ! -d "haproxy-$VERSION" ]; then
  tar xzf haproxy-$VERSION.tar.gz
fi

cd haproxy-$VERSION
echo "[*] Собираю HAProxy..."
make TARGET=linux-glibc USE_OPENSSL=1 USE_ZLIB=1 USE_PCRE=1
make install-bin PREFIX="$PREFIX"

cd "$PREFIX"

if [ ! -f "$CONF" ]; then
  echo "[*] Конфиг не найден, создаю дефолтный $CONF"
  cat > "$CONF" <<EOF
global
    log stdout format raw local0

defaults
    mode http
    timeout connect 5s
    timeout client  30s
    timeout server  30s

frontend http-in
    bind *:8080
    default_backend servers

backend servers
    server s1 127.0.0.1:8000 maxconn 32
EOF
fi

echo "[*] Запускаю HAProxy..."
"$PREFIX"/sbin/haproxy -f "$CONF" -db &
echo "[+] Готово! HAProxy установлен в $PREFIX и запущен."
