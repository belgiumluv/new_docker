# ==============================================================================
# Dockerfile — единый контейнер для sing-box + haproxy + vpnserver + Python
# Всё живёт в /app, без systemd. Готов для Docker и (при желании) K8s.
# Структура репозитория (важное):
#   bin/        — твои бинарники (sing-box, haproxy, vpnserver, etc.)
#   scripts/    — твои .sh/.py скрипты (мы копируем их в /app/bin)
#   docker/     — entrypoint.sh (переносим в /app/entrypoint.sh)
#   archives/   — (опц.) haproxy-etc.tar.gz (можно распаковать в /app/config/haproxy)
#   config/     — монтируй RW извне (docker-compose), чтобы vpnserver писал в server.json
# ==============================================================================

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# --- Базовые пакеты -----------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl jq \
    python3 python3-venv python3-pip python3-cffi \
    sqlite3 \
    supervisor \
    inotify-tools \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN update-ca-certificates

# --- Python зависимости для скриптов (.py) ------------------------------------
#  - PyNaCl: для 10_mutate_server_json.py (генерация reality keypair)
#  - requests: HTTP-запросы
#  - PyYAML: для copy_files.py (парсинг map.yml)
RUN pip3 install --no-cache-dir \
    pynacl==1.5.0 \
    requests \
    PyYAML

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

# --- Копирование всех файлов проекта -----------------------------------------
COPY . /app

# --- (Опц.) Распаковка архива HAProxy при сборке -----------------------------
# Если в репозитории есть archives/haproxy-etc.tar.gz и хочешь развернуть его
# в /app/config/haproxy на этапе сборки — оставь этот блок включённым.
RUN if [ -f /app/archives/haproxy-etc.tar.gz ]; then \
      mkdir -p /app/config/haproxy && \
      tar -xzf /app/archives/haproxy-etc.tar.gz -C /app/config/haproxy --strip-components=1 && \
      echo "[ok] extracted archives/haproxy-etc.tar.gz to /app/config/haproxy"; \
    else \
      echo "[info] no archives/haproxy-etc.tar.gz — skipping extraction"; \
    fi

# --- Подготовка entrypoint и скриптов -----------------------------------------
# 1) Если entrypoint лежит в docker/ — перенесём в /app/entrypoint.sh
# 2) Копируем скрипты из scripts/ в /app/bin (если есть), делаем исполняемыми
# 3) Чистим возможные CRLF в entrypoint
RUN if [ -f /app/docker/entrypoint.sh ]; then \
      cp /app/docker/entrypoint.sh /app/entrypoint.sh; \
    fi && \
    mkdir -p /app/bin && \
    cp -r /app/scripts/* /app/bin/ 2>/dev/null || true && \
    find /app/bin -type f -exec chmod +x {} \; || true && \
    chmod +x /app/entrypoint.sh 2>/dev/null || true && \
    sed -i 's/\r$//' /app/entrypoint.sh 2>/dev/null || true

# --- Проверка наличия бинарников (если у тебя они в bin/) ---------------------
# Эти команды не валят сборку, но помогут увидеть версии в логах build'а.
RUN ls -l /app/bin || true && \
    /app/bin/sing-box version || true && \
    /app/bin/haproxy -v || true && \
    /app/bin/vpnserver --help || true

# --- Права доступа ------------------------------------------------------------
RUN chown -R ${APP_UID}:${APP_GID} /app

USER ${APP_UID}:${APP_GID}

# --- Порты --------------------------------------------------------------------
EXPOSE 80 443

# --- Healthcheck (простой TCP GET на 80) --------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD bash -lc 'exec 3<>/dev/tcp/127.0.0.1/80; echo -e "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" >&3; cat <&3 >/dev/null || exit 1'

# --- Старт через tini -> entrypoint ------------------------------------------
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
