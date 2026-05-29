FROM node:20-bookworm-slim

RUN apt-get update && apt-get install -y \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libdbus-1-3 libxkbcommon0 libatspi2.0-0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libasound2 libpango-1.0-0 libcairo2 \
    xvfb x11vnc novnc websockify fluxbox \
    fonts-liberation fonts-noto-color-emoji wget ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

# Install REAL Google Chrome (stable). NotebookLM silently refuses write
# operations (add source) when it detects the Patchright/chromium headless
# environment — read ops (ask, download) still work, but creating a source
# never persists and no save RPC is even sent. Running through the genuine
# google-chrome-stable channel (BROWSER_CHANNEL=chrome) avoids that detection.
RUN wget -q -O /usr/share/keyrings/google-chrome.gpg.asc https://dl.google.com/linux/linux_signing_key.pub \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg.asc] http://dl.google.com/linux/chrome/deb/ stable main" \
       > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r notebooklm && useradd -r -g notebooklm -d /home/notebooklm notebooklm \
    && mkdir -p /home/notebooklm /app /data \
    && chown -R notebooklm:notebooklm /home/notebooklm /app /data \
    && mkdir -p /tmp/.X11-unix \
    && chmod 1777 /tmp/.X11-unix

WORKDIR /app

# Copier package files
COPY --chown=notebooklm:notebooklm package*.json ./

USER notebooklm

# Installer TOUTES les dépendances (avec devDependencies pour TypeScript)
RUN npm ci --ignore-scripts

# Copier les sources AVANT de builder
COPY --chown=notebooklm:notebooklm src/ ./src/
COPY --chown=notebooklm:notebooklm tsconfig*.json ./

# Builder
RUN npm run build

# Copier scripts
COPY --chown=notebooklm:notebooklm scripts/ ./scripts/

# Supprimer les devDependencies après le build
RUN npm prune --omit=dev

# Installer le browser. chromium stays as a fallback; google-chrome-stable
# (installed above) is used at runtime via BROWSER_CHANNEL=chrome.
RUN npx patchright install chromium

USER root
RUN chmod +x /app/scripts/*.sh
USER notebooklm

ENV NODE_ENV=production \
    HTTP_PORT=3000 \
    HTTP_HOST=0.0.0.0 \
    HEADLESS=true \
    NOTEBOOKLM_DATA_DIR=/data \
    PLAYWRIGHT_BROWSERS_PATH=/home/notebooklm/.cache/ms-playwright \
    DISPLAY=:99 \
    NOVNC_PORT=6080

EXPOSE 3000 6080

# The HTTP server shares its Node event loop with Patchright/Chromium. During
# a browser launch or a heavy page operation (add_source, content.generate)
# the loop is busy and /health briefly returns "Connection refused". With the
# old 3×30s/10s-start-period policy three such blips in a row marked the
# container unhealthy and Swarm killed it MID-OPERATION — tearing down the MCP
# session and the in-flight notebook action. Loosen it so only a genuine
# multi-minute outage trips it: long start-period for the lazy Chrome boot,
# and enough retries to ride out any single browser operation.
HEALTHCHECK --interval=30s --timeout=15s --start-period=120s --retries=10 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

VOLUME ["/data"]

CMD ["/app/scripts/docker-entrypoint.sh"]
