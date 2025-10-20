# ==============================================================================
# Dockerfile — единый контейнер для sing-box + haproxy + vpnserver + Python
# Работает в Kubernetes, всё в /app, без systemd и установки системных сервисов
# ==============================================================================

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# --- Базовые пакеты -----------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl jq \
    python3 python3-venv python3-pip \
    sqlite3 \
    supervisor \
    inotify-tools \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN update-ca-certificates

# --- Пользователь без root ----------------------------------------------------
ARG APP_UID=65532
ARG APP_GID=65532
RUN groupadd -g ${APP_GID} appgroup && \
    useradd -m -d /home/appuser -u ${APP_UID} -g ${APP_GID} -s /bin/bash appuser

# --- Переменные окружения -----------------------------------------------------
ENV APP_ROOT=/app \
    APP_CFG=/app/config \
    APP_DATA=/app/data \
    SQLITE_PATH=/app/data/bd/bd.db \
    TLS_DIR=/app/tls \
    PATH="/app/bin:$PATH"

# --- Каталоги приложения ------------------------------------------------------
RUN mkdir -p /app /app/config /app/data /app/tls /app/data/run /app/data/logs

# --- Копирование всех файлов проекта ------------------------------------------
COPY . /app

# --- Исполняемые файлы --------------------------------------------------------
RUN chmod +x /app/entrypoint.sh || true && \
    find /app/bin -type f -exec chmod +x {} \; || true

# --- Проверка наличия бинарников ----------------------------------------------
RUN ls -l /app/bin && \
    /app/bin/sing-box version || true && \
    /app/bin/haproxy -v || true && \
    /app/bin/vpnserver --help || true

# --- Права доступа ------------------------------------------------------------
RUN chown -R ${APP_UID}:${APP_GID} /app

USER ${APP_UID}:${APP_GID}

# --- Сетевые порты ------------------------------------------------------------
EXPOSE 80 443

# --- Healthcheck --------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD bash -lc 'exec 3<>/dev/tcp/127.0.0.1/80; echo -e "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" >&3; cat <&3 >/dev/null || exit 1'

# --- Запуск -------------------------------------------------------------------
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
