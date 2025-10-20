#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import socket
import requests

def get_public_ip(timeout: int = 5) -> str:
    """Возвращает публичный IP-адрес текущего узла."""
    try:
        resp = requests.get("https://ifconfig.me", timeout=timeout)
        resp.raise_for_status()
        return resp.text.strip()
    except Exception as e:
        return f"Error: {e}"

def get_reverse_dns(ip: str):
    """
    PTR-запись (reverse DNS) для IP.
    Возвращает имя хоста или None, если записи нет.
    """
    try:
        return socket.gethostbyaddr(ip)[0]
    except (socket.herror, socket.gaierror, OSError):
        return None

if __name__ == "__main__":
    ip = get_public_ip()
    print(f"Public IP: {ip}")
    if ip and not ip.startswith("Error:"):
        rdns = get_reverse_dns(ip)
        if rdns:
            print(f"Reverse DNS: {rdns}")
        else:
            print("No reverse DNS (PTR record not set)")
