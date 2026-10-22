#!/usr/bin/env python3
"""Minimal client for the blender_mcp addon's socket protocol (port 9876).

Sends {"type": "execute_code", "params": {"code": ...}} commands and prints
the JSON response. Used by the grassland modeling workflow.
"""

import json
import socket
import sys


def send_command(command: dict, host: str = "127.0.0.1", port: int = 9876, timeout: float = 120.0) -> dict:
    client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect((host, port))
    try:
        client.sendall(json.dumps(command).encode("utf-8"))
        buffer = b""
        while True:
            chunk = client.recv(65536)
            if not chunk:
                break
            buffer += chunk
            try:
                return json.loads(buffer.decode("utf-8"))
            except json.JSONDecodeError:
                continue
    finally:
        client.close()
    raise RuntimeError("connection closed before a full JSON response")


def run(code: str) -> dict:
    return send_command({"type": "execute_code", "params": {"code": code}})


if __name__ == "__main__":
    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as fh:
        payload = fh.read()
    response = run(payload)
    print(json.dumps(response, indent=2, ensure_ascii=False)[:8000])
