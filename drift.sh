#!/bin/sh
# drift on or off: starts the snow if it isn't falling, stops it if it is.
#   drift mouse [on|off]     the snow parting around the cursor, and the cursor sweeping settled snow off
#   drift behind [on|off]    the far snow, falling behind the windows
# Without on or off, those two switch over. The snow running picks the change up at once.
# Run from the launcher (no terminal), it says what it did in a notification.
DIR=/run/media/d/SD128/drift
PID="${XDG_RUNTIME_DIR:-/tmp}/drift.pid"
SET="$HOME/.config/drift/settings.json"

case "$1" in
mouse|behind)
    key=$1; [ "$key" = mouse ] && key=cursor
    said=$(python3 -I -c '
import json, os, sys
path, key, want = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        cfg = json.load(f)
except (OSError, ValueError):
    cfg = {}
now = {"on": True, "off": False}.get(want, not cfg.get(key, True))
cfg[key] = now
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:                 # in place: the running snow watches this file
    json.dump(cfg, f, indent=2)
    f.write("\n")
print(("mouse effect" if key == "cursor" else "snow behind windows") + ": " + ("on" if now else "off"))
' "$SET" "$key" "$2")
    echo "$said"
    [ -t 1 ] || notify-send -a drift -i weather-snow drift "$said"
    exit ;;
esac

if [ -f "$PID" ] && kill "$(cat "$PID")" 2>/dev/null; then
    rm -f "$PID"
else
    # low priority: any program that wants the processor gets it first, and the snow just slows a little
    setsid nice -n 10 qs -p "$DIR" >/dev/null 2>&1 &
    echo $! > "$PID"
fi
