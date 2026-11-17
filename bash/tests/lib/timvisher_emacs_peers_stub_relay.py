#!/usr/bin/env python3

import os
import socket
import sys
import time

sock_path, state = sys.argv[1], sys.argv[2]


def read(name, default):
    try:
        with open(os.path.join(state, name)) as f:
            return f.read().strip()
    except FileNotFoundError:
        return default


with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.bind(sock_path)
    s.listen(8)
    n = 0
    while True:
        conn, _ = s.accept()
        with conn:
            if read("mode", "normal") == "silent":
                time.sleep(7)
                continue
            buf = bytearray()
            while chunk := conn.recv(65536):
                buf.extend(chunk)
            n += 1
            os.makedirs(os.path.join(state, "requests"), exist_ok=True)
            with open(os.path.join(state, "requests", f"{n:03d}"), "wb") as f:
                f.write(bytes(buf))
            op = "send"
            for line in buf.decode().split("\n\n", 1)[0].splitlines():
                if line.lower().startswith("op:"):
                    op = line.split(":", 1)[1].strip()
            if op == "ping":
                conn.sendall(b"pong\n")
            elif op == "ls":
                conn.sendall(b"ok\n" + read("listing", '{"schema_version":1,"sessions":[]}').encode() + b"\n")
            else:
                conn.sendall(read("reply", "submitted").encode() + b"\n")
