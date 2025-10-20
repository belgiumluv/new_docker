#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import requests

# ============================================
# Контейнерные пути / ENV
# ============================================
APP_ROOT = os.getenv("APP_ROOT", "/app")
APP_DATA = os.getenv("APP_DATA", os.path.join(APP_ROOT, "data"))
APP_CFG  = os.getenv("APP_CFG",  os.path.join(APP_ROOT, "config"))

os.makedirs(APP_DATA, exist_ok=True)

SERVERLIST_PATH = os.path.join(APP_CFG, "serverlist.json")
OUT_PATH        = os.getenv("SERVER_CONF_JSON", os.path.join(APP_DATA, "server_configuration.json"))

# ============================================
# Утилиты
# ============================================
def get_public_ip() -> str:
    try:
        resp = requests.get("https://api.ipify.org?format=text", timeout=5)
        resp.raise_for_status()
        return resp.text.strip()
    except Exception as e:
        return f"Error: {e}"

# ============================================
# Основная логика
# ============================================
def main():
    current_ip = get_public_ip()
    list_dump = []

    if not os.path.exists(SERVERLIST_PATH):
        raise FileNotFoundError(f"serverlist.json не найден: {SERVERLIST_PATH}")

    with open(SERVERLIST_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # Ищем домен по текущему IP
    domain = data.get(current_ip)
    if domain is not None:
        list_dump = [current_ip, domain]
    else:
        # Если IP не найден, сохраняем пустую структуру, но явно сигнализируем
        list_dump = [current_ip, None]

    # Пишем результат в /app/data/server_configuration.json
    with open(OUT_PATH, 'w', encoding='utf-8') as f:
        json.dump(list_dump, f, ensure_ascii=False, indent=4)

    print(f"Wrote server configuration to: {OUT_PATH}")
    if domain is None:
        print(f"Warning: current IP {current_ip} not found in serverlist.json")

if __name__ == "__main__":
    main()
