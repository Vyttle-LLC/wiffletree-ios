#!/usr/bin/env python3
"""Prepares a headless Wiffletree host for the end-to-end check over its socket: creates a
project, turns remote access on, opens pairing mode and prints the pairing QR code's payload.

Usage: host_socket.py <data folder> <client credential> <project name>
"""
import json
import socket
import sys
import uuid


def main(data_dir: str, credential: str, project: str) -> None:
    connection = socket.socket(socket.AF_UNIX)
    connection.connect(f"{data_dir}/host.sock")
    lines = connection.makefile("rwb")

    def send(value: dict) -> None:
        lines.write(json.dumps(value).encode() + b"\n")
        lines.flush()

    def command(kind: str, **fields):
        request_id = str(uuid.uuid4())
        send({"version": 2, "id": request_id, "command": {"type": kind, **fields}})
        while True:
            reply = json.loads(lines.readline())
            if reply.get("id") == request_id:
                if reply.get("error"):
                    sys.exit(f"{kind}: {reply['error']}")
                return reply.get("result")

    send({"hello": {
        "protocols": [2, 2],
        "app_version": "e2e",
        "client": {"name": "wiffletree-ios end-to-end", "kind": "script"},
        "capabilities": [],
        "credential": credential,
    }})
    answer = json.loads(lines.readline())
    if "welcome" not in answer:
        sys.exit(f"The host refused Hello: {answer}")

    command("create_project", name=project)
    access = command("set_remote_access", enabled=True)
    if access.get("error"):
        sys.exit(f"Remote access is on but not listening: {access['error']}")
    command("open_pairing")
    print(json.dumps(command("pairing_qr")["payload"]))


if __name__ == "__main__":
    main(*sys.argv[1:4])
