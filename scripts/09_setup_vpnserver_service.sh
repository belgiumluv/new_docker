#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/app}"
APP_CFG="${APP_CFG:-$APP_ROOT/config}"
APP_DATA="${APP_DATA:-$APP_ROOT/data}"

RUN_DIR="${RUN_DIR:-$APP_DATA/run}"
LOG_DIR="${LOG_DIR:-$APP_DATA/logs}"
SUPERVISOR_CONF="${SUPERVISOR_CONF:-$APP_CFG/supervisord.conf}"

SINGBOX_SCRIPT="$APP_ROOT/bin/07_setup_singbox_full.sh"
HAPROXY_SCRIPT="$APP_ROOT/bin/08_deploy_haproxy_etc.sh"

mkdir -p "$RUN_DIR" "$LOG_DIR" "$APP_CFG"

# sanity checks
[[ -x "$SINGBOX_SCRIPT" ]] || { echo "[err] not exec: $SINGBOX_SCRIPT"; exit 2; }
[[ -x "$HAPROXY_SCRIPT" ]] || { echo "[err] not exec: $HAPROXY_SCRIPT"; exit 2; }

cat >"$SUPERVISOR_CONF" <<EOF
[unix_http_server]
file=$RUN_DIR/supervisor.sock

[supervisord]
logfile=$LOG_DIR/supervisord.log
pidfile=$RUN_DIR/supervisord.pid
childlogdir=$LOG_DIR
loglevel=info
nodaemon=false

[rpcinterface:supervisor]
supervisor.rpcinterface_factory=supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix://$RUN_DIR/supervisor.sock

; ---------------- Programs ----------------

; sing-box (watch mode)
[program:singbox]
command=/bin/bash -lc 'APP_ROOT=$APP_ROOT APP_CFG=$APP_CFG APP_DATA=$APP_DATA RUN_DIR=$RUN_DIR LOG_DIR=$LOG_DIR RUN_MODE=watch "$SINGBOX_SCRIPT"'
autostart=true
autorestart=true
stopsignal=TERM
stdout_logfile=$LOG_DIR/singbox.supervisor.out.log
stderr_logfile=$LOG_DIR/singbox.supervisor.err.log
startsecs=2
stopwaitsecs=10
; переменные жёстко подставлены в команду:
environment=APP_ROOT="$APP_ROOT",APP_CFG="$APP_CFG",APP_DATA="$APP_DATA",RUN_DIR="$RUN_DIR",LOG_DIR="$LOG_DIR",RUN_MODE="watch",SINGBOX_SCRIPT="$SINGBOX_SCRIPT"

; haproxy (watch mode)
[program:haproxy]
command=/bin/bash -lc 'APP_ROOT=$APP_ROOT APP_CFG=$APP_CFG APP_DATA=$APP_DATA RUN_DIR=$RUN_DIR LOG_DIR=$LOG_DIR RUN_MODE=watch "$HAPROXY_SCRIPT"'
autostart=true
autorestart=true
stopsignal=TERM
stdout_logfile=$LOG_DIR/haproxy.supervisor.out.log
stderr_logfile=$LOG_DIR/haproxy.supervisor.err.log
startsecs=2
stopwaitsecs=10
environment=APP_ROOT="$APP_ROOT",APP_CFG="$APP_CFG",APP_DATA="$APP_DATA",RUN_DIR="$RUN_DIR",LOG_DIR="$LOG_DIR",RUN_MODE="watch",HAPROXY_SCRIPT="$HAPROXY_SCRIPT"
EOF

echo "[ok ] created: $SUPERVISOR_CONF"
