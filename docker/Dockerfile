# ==============================================================================
# Dockerfile — единый контейнер для sing-box + haproxy + vpnserver + Python
# Всё живёт в /app, без systemd. Готов для Docker (и при желании K8s).
# ==============================================================================

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# --- Базовые пакеты + python-зависимости через APT ---------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl jq \
    python3 python3-venv python3-pip python3-cffi \
    python3-nacl python3-requests python3-yaml \
    sqlite3 \
    supervisor \
    inotify-tools \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends certbot && rm -rf /var/lib/apt/lists/*

  RUN update-ca-certificates
  
RUN apt-get update && apt-get install -y --no-install-recommends libcap2-bin && rm -rf /var/lib/apt/lists/*

# Разрешаем процессам на базе python3 слушать порты <1024
RUN setcap 'cap_net_bind_service=+ep' /usr/bin/python3.11 || setcap 'cap_net_bind_service=+ep' /usr/bin/python3 || true

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
WORKDIR /app

# --- Копирование проекта ------------------------------------------------------
COPY . /app

# --- (опц.) Распаковка HAProxy архива ----------------------------------------
# --- (опц.) Распаковка HAProxy архива ----------------------------------------
RUN if [ -f /app/archives/haproxy-etc.tar.gz ]; then \
      mkdir -p /app/config/haproxy && \
      tar -xzf /app/archives/haproxy-etc.tar.gz -C /app/config/haproxy --strip-components=1 && \
      echo "[ok] extracted archives/haproxy-etc.tar.gz to /app/config/haproxy"; \
    else \
      echo "[info] no archives/haproxy-etc.tar.gz — skipping extraction"; \
    fi


# --- Подготовка entrypoint и скриптов ----------------------------------------
RUN if [ -f /app/docker/entrypoint.sh ]; then \
      cp /app/docker/entrypoint.sh /app/entrypoint.sh; \
    fi && \
    mkdir -p /app/bin && \
    cp -r /app/scripts/* /app/bin/ 2>/dev/null || true && \
    find /app/bin -type f -exec chmod +x {} \; || true && \
    chmod +x /app/entrypoint.sh 2>/dev/null || true && \
    sed -i 's/\r$//' /app/entrypoint.sh 2>/dev/null || true

# --- Проверка наличия бинарников (не критично) --------------------------------
RUN ls -l /app/bin || true && \
    /app/bin/sing-box version || true && \
    /app/bin/haproxy -v || true && \
    /app/bin/vpnserver --help || true

# --- Права --------------------------------------------------------------------
RUN chown -R ${APP_UID}:${APP_GID} /app
USER ${APP_UID}:${APP_GID}

# --- Порты --------------------------------------------------------------------
EXPOSE 80 443

# --- Healthcheck --------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD bash -lc 'exec 3<>/dev/tcp/127.0.0.1/80; echo -e "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" >&3; cat <&3 >/dev/null || exit 1'

# --- Запуск -------------------------------------------------------------------
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
