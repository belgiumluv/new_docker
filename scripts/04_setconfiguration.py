#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import requests
import json
import sqlite3

# ============================================
# Контейнерные пути / ENV
# ============================================
APP_ROOT = os.getenv("APP_ROOT", "/app")
APP_DATA = os.getenv("APP_DATA", os.path.join(APP_ROOT, "data"))
APP_CFG  = os.getenv("APP_CFG",  os.path.join(APP_ROOT, "config"))
SQLITE_PATH = os.getenv("SQLITE_PATH", os.path.join(APP_DATA, "bd", "bd.db"))

os.makedirs(os.path.dirname(SQLITE_PATH), exist_ok=True)
os.makedirs(APP_DATA, exist_ok=True)

# ============================================
# Функции
# ============================================
def get_public_ip() -> str:
    """Получает текущий публичный IP-адрес."""
    try:
        resp = requests.get("https://api.ipify.org?format=text", timeout=5)
        return resp.text.strip()
    except Exception as e:
        return f"Error: {e}"

# ============================================
# Основная логика
# ============================================
db_path = SQLITE_PATH
list_serverconf = []

current_ip = get_public_ip()

# Загружаем serverlist.json (из /app/config)
serverlist_path = os.path.join(APP_CFG, "serverlist.json")
if not os.path.exists(serverlist_path):
    raise FileNotFoundError(f"Файл serverlist.json не найден по пути {serverlist_path}")

with open(serverlist_path, "r", encoding='utf-8') as file:
    data = json.load(file)
    domain = None
    for ip, dom in data.items():
        if ip == current_ip:
            list_serverconf = [str(ip), str(dom)]
            domain = dom
            break

# Проверка: если IP не найден
if not list_serverconf:
    raise ValueError(f"Текущий IP {current_ip} отсутствует в serverlist.json")

# ============================================
# Сохраняем конфигурацию в JSON и БД
# ============================================
# /app/data/server_configuration.json
server_conf_path = os.path.join(APP_DATA, "server_configuration.json")
with open(server_conf_path, "w", encoding='utf-8') as file:
    json.dump(list_serverconf, file, ensure_ascii=False, indent=4)

# Создаём таблицу в SQLite
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("""
CREATE TABLE IF NOT EXISTS server_conf (
    ip TEXT,
    domain TEXT
)
""")
conn.commit()

# Вставка данных
cur.execute("INSERT INTO server_conf (ip, domain) VALUES (?, ?)", (list_serverconf[0], list_serverconf[1]))
conn.commit()
conn.close()

# ============================================
# Создаём файл с доменом
# ============================================
domain_txt_path = os.path.join(APP_DATA, "domain.txt")
with open(domain_txt_path, 'w', encoding='utf-8') as file:
    file.write(domain)

print(f"Server configuration saved for IP={list_serverconf[0]}, domain={domain}")
