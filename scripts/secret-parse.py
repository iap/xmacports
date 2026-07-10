#!/usr/bin/env python3
"""Parse decrypted SOPS secrets YAML.

Reads YAML from stdin.
Usage:
  secret-parse.py get <namespace> <key>
  secret-parse.py list [namespace]
"""

import sys

import yaml


def _load() -> dict:
    try:
        return yaml.safe_load(sys.stdin) or {}
    except Exception as e:  # noqa: BLE001 - surface parse errors to stderr
        print(f"yaml parse error: {e}", file=sys.stderr)
        sys.exit(1)


def _get(ns: str, key: str) -> None:
    data = _load()
    node = data.get(ns, {})
    value = node.get(key) if isinstance(node, dict) else None
    if value is None:
        sys.exit(1)
    print(value, end="")


def _list(ns: str) -> None:
    data = _load()
    if ns:
        for key in data.get(ns, {}) or {}:
            print(key)
        return
    for ns_name, values in data.items():
        print(f"[{ns_name}]")
        for key in values or {}:
            print(f"  {key}")


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: secret-parse.py get <ns> <key> | list [ns]", file=sys.stderr)
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == "get":
        if len(sys.argv) != 4:
            print("usage: secret-parse.py get <ns> <key>", file=sys.stderr)
            sys.exit(2)
        _get(sys.argv[2], sys.argv[3])
    elif cmd == "list":
        _list(sys.argv[2] if len(sys.argv) > 2 else "")
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
