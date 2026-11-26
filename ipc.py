#!/usr/bin/env python3
"""drift's eyes: asks Hyprland where the cursor and the windows are, and prints what changed, a line each.

  C <x> <y>                      the cursor, about 25 times a second, only when it moved
  W <json>                       the windows, when anything about them changed:
                                 [{"a": address, "x", "y", "w", "h", "m": monitor name, "v": on a shown workspace, "f": fullscreen}]
  M <json>                       the monitors: [{"n": name, "x", "y"}]
  F <address>                    the focused window (empty when none)
"""

import json
import os
import socket
import sys
import time

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid()), "hypr",
                    os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""), ".socket.sock")


def ask(what: str) -> str:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1.0)
    try:
        s.connect(SOCK)
        s.sendall(what.encode())
        out = b""
        while True:
            b = s.recv(65536)
            if not b:
                break
            out += b
        return out.decode(errors="replace")
    finally:
        s.close()


def main() -> None:
    last_c = last_w = last_m = last_f = None
    tick = 0
    while True:
        try:
            c = ask("cursorpos").strip()
            if c != last_c:
                x, y = (int(float(v)) for v in c.split(","))
                print(f"C {x} {y}", flush=True)
                last_c = c
            if tick % 3 == 0:
                f = json.loads(ask("j/activewindow") or "{}").get("address", "")
                if f != last_f:
                    print("F " + f, flush=True)
                    last_f = f
            if tick % 6 == 0:
                mons = json.loads(ask("j/monitors"))
                shown = {m["activeWorkspace"]["id"] for m in mons} | {m["specialWorkspace"]["id"] for m in mons if m.get("specialWorkspace", {}).get("id")}
                m = json.dumps([{"n": x["name"], "x": x["x"], "y": x["y"]} for x in mons], separators=(",", ":"))
                if m != last_m:
                    print("M " + m, flush=True)
                    last_m = m
                wins = [{"a": w["address"], "x": w["at"][0], "y": w["at"][1], "w": w["size"][0], "h": w["size"][1],
                         "m": next((x["name"] for x in mons if x["id"] == w["monitor"]), ""),
                         "v": w["workspace"]["id"] in shown and not w.get("hidden"), "f": bool(w.get("fullscreen"))}
                        for w in json.loads(ask("j/clients")) if w.get("mapped", True)]
                w = json.dumps(wins, separators=(",", ":"))
                if w != last_w:
                    print("W " + w, flush=True)
                    last_w = w
        except BrokenPipeError:
            sys.exit(0)
        except (OSError, ValueError, KeyError, TypeError):
            time.sleep(1.0)
        tick += 1
        time.sleep(0.04)


if __name__ == "__main__":
    main()
