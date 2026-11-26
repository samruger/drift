#!/bin/sh
# drift on or off: starts the snow if it isn't falling, stops it if it is.
DIR=/run/media/d/SD128/drift
PID="${XDG_RUNTIME_DIR:-/tmp}/drift.pid"
if [ -f "$PID" ] && kill "$(cat "$PID")" 2>/dev/null; then
    rm -f "$PID"
else
    setsid qs -p "$DIR" >/dev/null 2>&1 &
    echo $! > "$PID"
fi
