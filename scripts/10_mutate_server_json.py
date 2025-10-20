#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import base64
import secrets
import string
import sqlite3
from random import randint
from nacl.public import PrivateKey

# =========================
# Контейнерные пути / ENV
# =========================
APP_ROOT = os.getenv("APP_ROOT", "/app")
APP_DATA = os.getenv("APP_DATA", os.path.join(APP_ROOT, "data"))
APP_CFG  = os.getenv("APP_CFG",  os.path.join(APP_ROOT, "config"))
SQLITE_PATH = os.getenv("SQLITE_PATH", os.path.join(APP_DATA, "bd", "bd.db"))

# Гарантируем наличие директорий
os.makedirs(os.path.dirname(SQLITE_PATH), exist_ok=True)
os.makedirs(APP_DATA, exist_ok=True)

# =========================
# Вспомогательные функции
# =========================
def generate_ss2022_password() -> str:
    key = os.urandom(32)  # 32 bytes = 256 bits
    return base64.b64encode(key).decode("utf-8")

def generateString(length: int = 22) -> str:
    chars = string.ascii_letters + string.digits
    return ''.join(secrets.choice(chars) for _ in range(length))

def b64url_nopad(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")

def generate_reality_keypair():
    sk = PrivateKey.generate()
    pk = sk.public_key
    priv = b64url_nopad(bytes(sk))
    pub  = b64url_nopad(bytes(pk))
    return priv, pub

# =========================
# Подготовка БД (SQLite)
# =========================
conn = sqlite3.connect(SQLITE_PATH, timeout=30, check_same_thread=False)
cur = conn.cursor()

cur.execute("""
CREATE TABLE IF NOT EXISTS fakedomain (
    reality   TEXT,
    shadowtls TEXT,
    hysteria  TEXT
)
""")

cur.execute("""
CREATE TABLE IF NOT EXISTS protocol_path (
    v10_trojan_grpc TEXT NOT NULL,
    v10_vless_grpc TEXT NOT NULL,
    v10_vmess_grpc TEXT NOT NULL,
    v10_vless_httpupgrade TEXT NOT NULL,
    v10_vless_tcp TEXT NOT NULL,
    v10_vmess_ws TEXT NOT NULL,
    v10_vmess_tcp TEXT NOT NULL,
    v10_vmess_httpupgrade TEXT NOT NULL,
    hysteria_in_50062 TEXT NOT NULL,
    realityin_43124 TEXT NOT NULL,
    ss_new TEXT NOT NULL,
    v10_trojan_tcp TEXT NOT NULL,
    v10_trojan_ws TEXT NOT NULL,
    v10_vless_ws TEXT NOT NULL
)
""")

cur.execute("""
CREATE TABLE IF NOT EXISTS realitykey (
    key TEXT
)
""")

conn.commit()

# =========================
# Выбор доменов-маскарадеров
# =========================
masq_path = os.path.join(APP_CFG, "masq_domain_list.json")
with open(masq_path, 'r', encoding='utf-8') as f:
    masq_data = json.load(f)

# Выбираем 3 уникальных домена из списка
list_selected = []
num = randint(0, len(masq_data))
list_selected.append(masq_data[num - 1])
num = randint(0, len(masq_data))
while True:
    if masq_data[num - 1] not in list_selected:
        list_selected.append(masq_data[num - 1])
        break
    num = randint(0, len(masq_data))
num = randint(0, len(masq_data))
while True:
    if masq_data[num - 1] not in list_selected:
        list_selected.append(masq_data[num - 1])
        break
    num = randint(0, len(masq_data))

# Сохраняем выбор для других скриптов
vibork_path = os.path.join(APP_DATA, "msq_domain_list_vibork.json")
with open(vibork_path, 'w', encoding='utf-8') as f:
    json.dump(list_selected, f, ensure_ascii=False, indent=4)

# Пишем в БД таблицу fakedomain
cur.execute(
    "INSERT INTO fakedomain (reality, shadowtls, hysteria) VALUES (?, ?, ?)",
    (list_selected[0], list_selected[1], list_selected[2])
)
conn.commit()

# =========================
# Читаем основной домен сервера
# (кладётся 04_setconfiguration.py)
# =========================
domain_txt_path = os.path.join(APP_DATA, "domain.txt")
with open(domain_txt_path, 'r', encoding='utf-8') as f:
    main_domain = f.read().strip()

# =========================
# Мутация server.json
# =========================
server_json_path = os.path.join(APP_CFG, "server.json")
with open(server_json_path, mode="r+", encoding="utf-8") as f:
    data = json.load(f)
    mainBlock = data.get("inbounds", [])
    changes_list = {}
    changes_listwith = {}
    publick = ""  # на случай отсутствия тега realityin_43124

    for protocol in mainBlock:
        tag = protocol.get("tag", "")

        if tag == "v10-trojan-grpc":
            transport = protocol.get("transport", {})
            transport["service_name"] = f'api{generateString()}'
            changes_list["v10-trojan-grpc"] = transport["service_name"]
            changes_listwith["v10_trojan_grpc"] = transport["service_name"]

        elif tag == "v10-vless-grpc":
            transport = protocol.get("transport", {})
            transport["service_name"] = f'api{generateString()}'
            changes_list["v10-vless-grpc"] = transport["service_name"]
            changes_listwith["v10_vless_grpc"] = transport["service_name"]

        elif tag == "v10-vmess-grpc":
            transport = protocol.get("transport", {})
            transport["service_name"] = f'api{generateString()}'
            changes_list["v10-vmess-grpc"] = transport["service_name"]
            changes_listwith["v10_vmess_grpc"] = transport["service_name"]

        elif tag == "v10-vless-httpupgrade":
            transport = protocol.get("transport", {})
            transport["path"] = f"/files{generateString()}"
            changes_list["v10-vless-httpupgrade"] = transport["path"]
            changes_listwith["v10_vless_httpupgrade"] = transport["path"]

        elif tag == "v10-vless-tcp":
            transport = protocol.get("transport", {})
            transport["path"] = f"/user{generateString()}"
            changes_list["v10-vless-tcp"] = transport["path"]
            changes_listwith["v10_vless_tcp"] = transport["path"]

        elif tag == "v10-vmess-ws":
            transport = protocol.get("transport", {})
            transport["path"] = f"/assets{generateString()}"
            changes_list["v10-vmess-ws"] = transport["path"]
            changes_listwith["v10_vmess_ws"] = transport["path"]

        elif tag == "v10-vmess-tcp":
            transport = protocol.get("transport", {})
            transport["path"] = f"/user{generateString()}"
            changes_list["v10-vmess-tcp"] = transport["path"]
            changes_listwith["v10_vmess_tcp"] = transport["path"]

        elif tag == "v10-vmess-httpupgrade":
            transport = protocol.get("transport", {})
            transport["path"] = f"/files{generateString()}"
            changes_list["v10-vmess-httpupgrade"] = transport["path"]
            changes_listwith["v10_vmess_httpupgrade"] = transport["path"]

        elif tag == "hysteria_in_50062":
            protocol["masquerade"] = f'https://{list_selected[2]}:80/'
            obfs = protocol.get("obfs", {})
            obfs["password"] = generateString()
            protocol["obfs"] = obfs
            changes_list["hysteria_in_50062"] = obfs["password"]
            changes_listwith["hysteria_in_50062"] = obfs["password"]
            tls = protocol.get("tls", {})
            tls["server_name"] = main_domain
            protocol["tls"] = tls

        elif tag == "realityin_43124":
            private, publick_val = generate_reality_keypair()
            publick = str(publick_val)
            tls = protocol.get("tls", {})
            reality = tls.get("reality", {})
            reality["private_key"] = private
            tls["reality"] = reality
            tls["server_name"] = list_selected[0]
            handshake = reality.get("handshake", {})
            handshake["server"] = list_selected[0]
            reality["handshake"] = handshake
            protocol["tls"] = tls
            changes_list["realityin_43124"] = private
            changes_listwith["realityin_43124"] = private

        elif tag == "ss-new":
            protocol["password"] = generate_ss2022_password()
            changes_list["ss-new"] = protocol["password"]
            changes_listwith["ss_new"] = protocol["password"]

        elif tag == "shadowtls":
            handshake = protocol.get("handshake", {})
            handshake["server"] = list_selected[1]
            protocol["handshake"] = handshake

        elif tag == "v10-trojan-tcp":
            transport = protocol.get("transport", {})
            transport["path"] = f"/user{generateString()}"
            changes_list["v10-trojan-tcp"] = transport["path"]
            changes_listwith["v10_trojan_tcp"] = transport["path"]

        elif tag == "v10-trojan-ws":
            transport = protocol.get("transport", {})
            transport["path"] = f"/assets{generateString()}"
            changes_list["v10-trojan-ws"] = transport["path"]
            changes_listwith["v10_trojan_ws"] = transport["path"]

        elif tag == "v10-vless-ws":
            transport = protocol.get("transport", {})
            transport["path"] = f"/assets{generateString()}"
            changes_list["v10-vless-ws"] = transport["path"]
            changes_listwith["v10_vless_ws"] = transport["path"]

        elif tag == "tuic_in_55851":
            tls = protocol.get("tls", {})
            tls["server_name"] = main_domain
            protocol["tls"] = tls

    # Записываем обновлённый server.json
    f.seek(0)
    json.dump(data, f, ensure_ascii=False, indent=4)
    f.truncate()

# =========================
# Запись результатов мутации
# =========================
# Вставка путей в БД
cols = ", ".join(changes_listwith.keys())
placeholders = ", ".join("?" for _ in changes_listwith)
values = tuple(changes_listwith.values())
cur.execute(f"INSERT INTO protocol_path ({cols}) VALUES ({placeholders})", values)

# Публичный ключ Reality (если есть)
if publick:
    cur.execute("INSERT INTO realitykey (key) VALUES (?)", (publick,))

conn.commit()
conn.close()

# Файл с изменениями для других шагов
changes_dict_path = os.path.join(APP_DATA, "changes_dict.json")
with open(changes_dict_path, 'w', encoding="utf-8") as f:
    json.dump(changes_list, f, ensure_ascii=False, indent=4)

print("done")
