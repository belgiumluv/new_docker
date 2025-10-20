#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import glob
import os
import shutil
import sys
import yaml
from pathlib import Path

# ============================================
# Парсер аргументов
# ============================================
def parse_args():
    p = argparse.ArgumentParser(description="Deploy files according to map.yml (container-safe version)")
    p.add_argument("--map", default="map.yml", help="path to map.yml")
    p.add_argument("--payload", default="payload", help="source payload directory")
    p.add_argument(
        "--root",
        default=os.getenv("APP_ROOT", "/app"),
        help="destination root prefix (default: /app for container use)"
    )
    p.add_argument("--dry", action="store_true", help="dry run (no changes)")
    return p.parse_args()

# ============================================
# Работа с map.yml
# ============================================
def load_rules(map_file: Path):
    doc = yaml.safe_load(map_file.read_text(encoding="utf-8"))
    # Поддержка формата {rules: [...]} или просто список
    rules = doc.get("rules", doc)
    if not isinstance(rules, list):
        raise ValueError("map.yml: 'rules' must be a list or contain key 'rules'")
    return rules

def ensure_dir(path: Path, dry: bool):
    if dry:
        return
    path.mkdir(parents=True, exist_ok=True)

def set_owner(path: Path, owner: str, dry: bool):
    if not owner:
        return
    try:
        user, group = owner.split(":")
    except ValueError:
        print(f"[warn] invalid owner '{owner}', expected 'user:group'")
        return
    if dry:
        return
    try:
        shutil.chown(path, user=user, group=group)
    except Exception as e:
        print(f"[warn] chown {owner} failed for {path}: {e}")

def copy_file(src: Path, dst: Path, owner: str, dry: bool):
    print(f"[copy] {src} -> {dst}")
    if dry:
        return
    ensure_dir(dst.parent, dry)
    shutil.copy2(src, dst)  # сохраняем время и права
    os.chmod(dst, src.stat().st_mode)
    set_owner(dst, owner, dry)

def apply_rule(rule: dict, payload_root: Path, dest_root: Path, dry: bool):
    src_pat = rule.get("from")
    to = rule.get("to")
    owner = rule.get("owner", "")

    if not src_pat or not to:
        print(f"[warn] invalid rule (need 'from' and 'to'): {rule}")
        return

    to_path = dest_root / to.lstrip("/")

    # Ищем соответствия
    matches = sorted(glob.glob(str((payload_root / src_pat).resolve()), recursive=True))
    if not matches:
        print(f"[warn] no matches for: {src_pat}")
        return

    to_is_dir_hint = str(to).endswith("/") or (to_path.exists() and to_path.is_dir())
    multiple_sources = len(matches) > 1

    for m in matches:
        s = Path(m)
        if s.is_dir():
            target_dir = to_path / s.name if to_is_dir_hint else to_path
            print(f"[dir ] {s} -> {target_dir}")
            if not dry:
                ensure_dir(target_dir, dry)
                shutil.copytree(s, target_dir, dirs_exist_ok=True)
                set_owner(target_dir, owner, dry)
            continue

        if to_is_dir_hint or multiple_sources:
            dst = to_path / s.name
        else:
            dst = to_path

        copy_file(s, dst, owner, dry)

# ============================================
# Основная функция
# ============================================
def main():
    args = parse_args()
    payload_root = Path(args.payload)
    map_file = Path(args.map)
    dest_root = Path(args.root)

    if not payload_root.exists():
        print(f"[err ] payload not found: {payload_root}", file=sys.stderr)
        sys.exit(2)
    if not map_file.exists():
        print(f"[err ] map.yml not found: {map_file}", file=sys.stderr)
        sys.exit(2)

    try:
        rules = load_rules(map_file)
    except Exception as e:
        print(f"[err ] {e}", file=sys.stderr)
        sys.exit(2)

    print(f"[info] payload={payload_root} map={map_file} root={dest_root} dry={args.dry}")
    for r in rules:
        apply_rule(r, payload_root, dest_root, args.dry)

    print("[done]")

if __name__ == "__main__":
    main()
