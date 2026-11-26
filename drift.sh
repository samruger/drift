#!/bin/sh
# drift on or off: starts the snow if it isn't falling, stops it if it is.
#   drift mouse [on|off]     the snow parting around the cursor, and the cursor sweeping settled snow off
#   drift behind [on|off]    the far snow, falling behind the windows
# Without on or off, those two switch over. The snow running picks the change up at once.
# Run from the launcher (no terminal), it says what it did in a notification.
# Where shell.qml is: $DRIFT_DIR, else beside this script, else ~/.local/share/drift (a copy or a link to the repo).
here=$(dirname "$(readlink -f "$0")")
for DIR in "$DRIFT_DIR" "$here" "${XDG_DATA_HOME:-$HOME/.local/share}/drift"; do
    [ -n "$DIR" ] && [ -f "$DIR/shell.qml" ] && break
done
PID="${XDG_RUNTIME_DIR:-/tmp}/drift.pid"
LINK="$HOME/.local/lib/drift/drift"
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

# running = the pid in the file is alive and is drift (a pid left from a crash may belong to something else by now)
pid=$(cat "$PID" 2>/dev/null)
if [ -n "$pid" ] && [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = drift ]; then
    kill "$pid"
    rm -f "$PID"
else
    [ -f "$DIR/shell.qml" ] || { echo "drift: can't find shell.qml (set DRIFT_DIR)" >&2; exit 1; }
    qs=$(command -v quickshell) || { echo "drift: needs Quickshell" >&2; exit 1; }
    # Quickshell is run through a link called drift, so the process is called drift (not qs) in top and btop.
    mkdir -p "$(dirname "$LINK")" && ln -sfn "$qs" "$LINK"
    # low priority: any program that wants the processor gets it first, and the snow just slows a little
    setsid nice -n 10 "$LINK" -p "$DIR" >/dev/null 2>&1 &
    echo $! > "$PID"
fi
