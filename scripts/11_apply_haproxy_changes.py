#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import re
import os
import shutil
from typing import Dict, List, Tuple, Optional

# =========================================================
# Контейнерные пути / ENV
# =========================================================
APP_ROOT = os.getenv("APP_ROOT", "/app")
APP_CFG  = os.getenv("APP_CFG",  os.path.join(APP_ROOT, "config"))
APP_DATA = os.getenv("APP_DATA", os.path.join(APP_ROOT, "data"))

HAP_PATH     = os.getenv("HAP_PATH", os.path.join(APP_CFG, "haproxy", "haproxy.cfg"))
CHANGES_PATH = os.getenv("CHANGES_PATH", os.path.join(APP_DATA, "changes_dict.json"))
DOMAIN_PATH  = os.getenv("DOMAIN_PATH", os.path.join(APP_DATA, "msq_domain_list_vibork.json"))

# =========================================================
# Настройки сопоставления тегов HAProxy
# =========================================================
TAG_TO_BACKENDS: Dict[str, List[str]] = {
    "v10-vless-ws": ["v10-vless-ws"],
    "v10-vless-grpc": ["v10-vless-grpc", "v10-vless-grpc-http"],
    "v10-vless-httpupgrade": ["v10-vless-httpupgrade"],
    "v10-vless-tcp": ["v10-vless-tcp", "v10-vless-tcp-http"],

    "v10-vmess-ws": ["v10-vmess-ws"],
    "v10-vmess-grpc": ["v10-vmess-grpc", "v10-vmess-grpc-http"],
    "v10-vmess-httpupgrade": ["v10-vmess-httpupgrade"],
    "v10-vmess-tcp": ["v10-vmess-tcp", "v10-vmess-tcp-http"],

    "v10-trojan-ws": ["v10-trojan-ws"],
    "v10-trojan-grpc": ["v10-trojan-grpc", "v10-trojan-grpc-http"],
    "v10-trojan-httpupgrade": ["v10-trojan-httpupgrade"],
    "v10-trojan-tcp": ["v10-trojan-tcp", "v10-trojan-tcp-http"],
}

# =========================================================
# Вспомогательные функции
# =========================================================
def _ensure_leading_slash(p: str) -> str:
    p = (p or "").strip()
    return p if (not p or p.startswith("/")) else f"/{p}"

def _backend_line_regex(backend_name: str) -> re.Pattern:
    return re.compile(rf'(use_backend\s+{re.escape(backend_name)}\s+if\s+\{{\s*path_beg\s+)(/[^ \}}\n]+)')

def _replace_paths(text: str, paths: Dict[str, str], notes: List[str]) -> str:
    for tag, new_val in (paths or {}).items():
        backends = TAG_TO_BACKENDS.get(tag)
        if not backends:
            notes.append(f"[WARN] Неизвестный тег '{tag}' — пропускаю.")
            continue

        new_path = _ensure_leading_slash(str(new_val))
        for be in backends:
            rx = _backend_line_regex(be)

            def _sub(m: re.Match) -> str:
                old = m.group(2)
                if old == new_path:
                    return m.group(1) + old
                notes.append(f"[PATH] {be}: {old} -> {new_path}")
                return m.group(1) + new_path

            text, n = rx.subn(_sub, text)
            if n == 0:
                notes.append(f"[MISS] use_backend {be} с path_beg не найден.")
    return text

def _replace_domains(text: str,
                     reality_server_name: Optional[str],
                     shadowtls_server_name: Optional[str],
                     notes: List[str]) -> str:
    """
    Меняем домены только если они переданы.
    """
    def sub_domain(all_text: str, old: str, new: str, label: str) -> str:
        rx_port = re.compile(rf'\b{re.escape(old)}:80\b')
        rx_plain = re.compile(rf'\b{re.escape(old)}\b')

        def _sub_port(m: re.Match) -> str:
            oldv = m.group(0)
            newv = f"{new}:80"
            if oldv != newv:
                notes.append(f"[HOST] {label}: {oldv} -> {newv}")
            return newv

        def _sub_plain(m: re.Match) -> str:
            oldv = m.group(0)
            newv = new
            if oldv != newv:
                notes.append(f"[HOST] {label}: {oldv} -> {newv}")
            return newv

        all_text, _ = rx_port.subn(_sub_port, all_text)
        all_text, _ = rx_plain.subn(_sub_plain, all_text)
        return all_text

    if reality_server_name:
        text = sub_domain(text, "www.habbo.com", reality_server_name, "Reality")

    if shadowtls_server_name:
        text = sub_domain(text, "www.shamela.ws", shadowtls_server_name, "ShadowTLS")

    return text

# =========================================================
# Основная функция изменения haproxy.cfg
# =========================================================
def apply_haproxy_changes(
    haproxy_path: str,
    path_changes: Optional[Dict[str, str]] = None,
    reality_server_name: Optional[str] = None,
    shadowtls_server_name: Optional[str] = None,
    out_path: Optional[str] = None,
    dry_run: bool = False,
) -> Tuple[str, List[str]]:

    with open(haproxy_path, "r", encoding="utf-8") as f:
        text = f.read()

    notes: List[str] = []

    if path_changes:
        text = _replace_paths(text, path_changes, notes)

    if reality_server_name or shadowtls_server_name:
        text = _replace_domains(text, reality_server_name, shadowtls_server_name, notes)

    if dry_run:
        return text, notes

    write_path = out_path or haproxy_path
    if os.path.abspath(write_path) == os.path.abspath(haproxy_path):
        shutil.copy2(haproxy_path, haproxy_path + ".bak")
        notes.append(f"[BACKUP] Создан бэкап: {haproxy_path}.bak")

    with open(write_path, "w", encoding="utf-8") as f:
        f.write(text)
    notes.append(f"[WRITE] Записано: {write_path}")

    return text, notes

# =========================================================
# Точка входа как самостоятельного скрипта
# =========================================================
if __name__ == "__main__":
    # Загружаем данные
    with open(DOMAIN_PATH, 'r', encoding='utf-8') as f:
        domain_list = json.load(f)

    with open(CHANGES_PATH, 'r', encoding='utf-8') as f:
        path_changes = json.load(f)

    reality = domain_list[0] if len(domain_list) > 0 else None
    shadowtls = domain_list[1] if len(domain_list) > 1 else None

    _, log = apply_haproxy_changes(
        haproxy_path=HAP_PATH,
        path_changes=path_changes,
        reality_server_name=reality,
        shadowtls_server_name=shadowtls,
        out_path=HAP_PATH,
        dry_run=False
    )

    print("\n".join(log))
