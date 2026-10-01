#!/usr/bin/env bash
#
# Start the TripMate AI (FastAPI) server.
#
# Before launching it kills whatever is already listening on the target port.
# A stale server silently kept serving old code on Windows ("pkill" does not
# touch native processes), so freeing the port first avoids that class of bug.
#
# Usage:
#   ./run.sh                  # serve on 127.0.0.1:8000
#   PORT=8080 ./run.sh        # serve on a custom port
#   ./run.sh --reload         # pass extra flags through to uvicorn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"

# --- locate the virtualenv interpreter (Windows Scripts/ or POSIX bin/) ---
if [ -x ".venv/Scripts/python.exe" ]; then
  PYTHON=".venv/Scripts/python.exe"
elif [ -x ".venv/bin/python" ]; then
  PYTHON=".venv/bin/python"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "Could not find a Python interpreter (expected .venv/ or python on PATH)." >&2
  exit 1
fi

# --- kill anything already listening on $PORT ---
kill_port() {
  local port="$1" pids=""

  # Windows / Git Bash:  TCP  127.0.0.1:PORT  ...  LISTENING  <pid>
  if command -v netstat >/dev/null 2>&1; then
    pids="$(netstat -ano 2>/dev/null | tr -d '\r' \
      | awk -v pat=":${port}$" '$1=="TCP" && $2 ~ pat && $NF ~ /^[0-9]+$/ {print $NF}' \
      | sort -u || true)"
  fi

  # POSIX fallbacks
  if [ -z "$pids" ] && command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -ti "tcp:$port" 2>/dev/null | sort -u || true)"
  fi
  if [ -z "$pids" ] && command -v fuser >/dev/null 2>&1; then
    pids="$(fuser "$port/tcp" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -u || true)"
  fi

  [ -z "$pids" ] && return 0

  for pid in $pids; do
    echo "Killing stale process $pid on port $port ..."
    if command -v taskkill >/dev/null 2>&1; then
      taskkill //F //PID "$pid" >/dev/null 2>&1 || true
    else
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
}

kill_port "$PORT"
sleep 1

echo "Starting TripMate AI on http://$HOST:$PORT (Ctrl+C to stop)"
exec "$PYTHON" -m uvicorn app:app --host "$HOST" --port "$PORT" "$@"
