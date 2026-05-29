#!/bin/bash
# Docker entrypoint for NotebookLM MCP Server
# Starts VNC services (for visual auth) and Node.js HTTP server
set -e
echo "==========================================="
echo "  NotebookLM MCP Server - Docker"
echo "==========================================="
echo ""
# Check if VNC should be started (default: yes in Docker)
ENABLE_VNC="${ENABLE_VNC:-true}"
if [ "$ENABLE_VNC" = "true" ]; then
    echo "[Entrypoint] Starting VNC services..."
    source /app/scripts/start-vnc.sh
    echo ""
    echo "[Entrypoint] VNC ready at: http://<host>:${NOVNC_PORT:-6080}/vnc.html"
    echo ""
else
    echo "[Entrypoint] VNC disabled (ENABLE_VNC=false)"
fi
# Clear stale Chrome singleton locks before launching. A persistent Chrome
# profile on a volume keeps SingletonLock/SingletonCookie/SingletonSocket
# symlinks; if the previous container was killed (Swarm rolling update, OOM,
# crash) without a clean Chrome shutdown, those locks survive and the next
# launch dies with "Target page, context or browser has been closed"
# (exit 21). Safe to delete on boot — only one container owns this profile.
DATA_DIR_CLEAN="${NOTEBOOKLM_DATA_DIR:-${DATA_DIR:-/data}}"
if [ -d "${DATA_DIR_CLEAN}/chrome_profile" ]; then
    echo "[Entrypoint] Clearing stale Chrome singleton locks in ${DATA_DIR_CLEAN}/chrome_profile..."
    rm -f "${DATA_DIR_CLEAN}/chrome_profile"/Singleton* 2>/dev/null || true
fi

# Render injecte automatiquement PORT, on l'utilise en priorité
export HTTP_PORT=${PORT:-${HTTP_PORT:-3000}}
echo "[Entrypoint] Starting Node.js HTTP server on port ${HTTP_PORT}..."
echo ""
# Start the Node.js server (foreground)
exec node dist/http-wrapper.js
