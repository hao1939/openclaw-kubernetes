#!/bin/bash
set -e

DISPLAY_NUM=${DISPLAY_NUM:-99}
SCREEN_RES=${SCREEN_RESOLUTION:-1920x1080x24}
VNC_PORT=${VNC_PORT:-5900}
NOVNC_PORT=${NOVNC_PORT:-6080}
TTYD_PORT=${TTYD_PORT:-7681}
TTYD_ENABLED=${TTYD_ENABLED:-true}
TTYD_BASE_PATH=${TTYD_BASE_PATH:-/ttyd/}
TAILSCALE_ENABLED=${TAILSCALE_ENABLED:-false}
TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-}
TAILSCALE_STATE_DIR=${TAILSCALE_STATE_DIR:-/var/lib/tailscale}
TAILSCALE_USERSPACE=${TAILSCALE_USERSPACE:-true}
TAILSCALE_EXTRA_ARGS=${TAILSCALE_EXTRA_ARGS:-}
TAILSCALE_SERVE_ENABLED=${TAILSCALE_SERVE_ENABLED:-false}
TAILSCALE_SERVE_PORT=${TAILSCALE_SERVE_PORT:-18789}
TAILSCALE_ACCEPT_DNS=${TAILSCALE_ACCEPT_DNS:-false}

cat > /tmp/supervisord.conf << EOF
[unix_http_server]
file=/tmp/supervisor.sock

[supervisorctl]
serverurl=unix:///tmp/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory=supervisor.rpcinterface:make_main_rpcinterface

[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0
pidfile=/tmp/supervisord.pid
environment=DISPLAY=":${DISPLAY_NUM}"

[program:xvfb]
command=Xvfb :${DISPLAY_NUM} -screen 0 ${SCREEN_RES} -ac +extension GLX +render -noreset
priority=10
autorestart=true
stdout_logfile=/dev/null
stderr_logfile=/dev/null

[program:fluxbox]
command=fluxbox
priority=20
autorestart=true
startretries=10
stdout_logfile=/dev/null
stderr_logfile=/dev/null

[program:x11vnc]
command=x11vnc -display :${DISPLAY_NUM} -forever -shared -rfbport ${VNC_PORT} -nopw -quiet -xkb -noxrecord -noxfixes -noxdamage
priority=20
autorestart=true
startretries=10
stdout_logfile=/dev/null
stderr_logfile=/dev/null

[program:novnc]
command=websockify --web /usr/share/novnc ${NOVNC_PORT} localhost:${VNC_PORT}
priority=30
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:chrome]
command=google-chrome --no-sandbox --disable-gpu --no-first-run --disable-dev-shm-usage --start-maximized --remote-debugging-port=18800 --user-data-dir=/home/vibe/.config/google-chrome/openclaw
priority=35
autorestart=true
startretries=5
startsecs=3
stdout_logfile=/dev/null
stderr_logfile=/dev/null

[program:openclaw]
command=openclaw gateway $* --allow-unconfigured
priority=40
autorestart=true
stopasgroup=true
killasgroup=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

if [ "$TTYD_ENABLED" = "true" ]; then
  cat >> /tmp/supervisord.conf << TTYD

[program:ttyd]
command=ttyd --port ${TTYD_PORT} --base-path ${TTYD_BASE_PATH} --writable zsh
priority=25
autorestart=true
startretries=5
stdout_logfile=/dev/null
stderr_logfile=/dev/null
TTYD
fi

if [ "$TAILSCALE_ENABLED" = "true" ]; then
  # Derive per-pod hostname: <prefix>-<ordinal> or fall back to pod name
  if [ -n "$TAILSCALE_HOSTNAME" ]; then
    POD_ORDINAL=${HOSTNAME##*-}
    if echo "$POD_ORDINAL" | grep -qE '^[0-9]+$'; then
      TS_HOST="${TAILSCALE_HOSTNAME}-${POD_ORDINAL}"
    else
      # Not a StatefulSet pod name — use full hostname as suffix
      TS_HOST="${TAILSCALE_HOSTNAME}-${HOSTNAME}"
    fi
  else
    TS_HOST="$HOSTNAME"
  fi

  # Build tailscaled flags
  TS_DAEMON_FLAGS="--state=${TAILSCALE_STATE_DIR}/tailscaled.state"
  if [ "$TAILSCALE_USERSPACE" = "true" ]; then
    TS_DAEMON_FLAGS="${TS_DAEMON_FLAGS} --tun=userspace-networking"
  else
    # Kernel networking requires /dev/net/tun
    sudo mkdir -p /dev/net
    sudo mknod /dev/net/tun c 10 200 2>/dev/null || true
    sudo chmod 600 /dev/net/tun
  fi

  # Build tailscale up flags
  TS_UP_FLAGS="--hostname=${TS_HOST}"
  if [ "$TAILSCALE_ACCEPT_DNS" = "true" ]; then
    TS_UP_FLAGS="${TS_UP_FLAGS} --accept-dns"
  else
    TS_UP_FLAGS="${TS_UP_FLAGS} --accept-dns=false"
  fi
  if [ -n "$TAILSCALE_EXTRA_ARGS" ]; then
    # Strip newlines/CRs to prevent supervisord config injection
    TAILSCALE_EXTRA_ARGS=$(printf '%s' "$TAILSCALE_EXTRA_ARGS" | tr -d '\n\r')
    TS_UP_FLAGS="${TS_UP_FLAGS} ${TAILSCALE_EXTRA_ARGS}"
  fi

  cat >> /tmp/supervisord.conf << TAILSCALE

[program:tailscaled]
command=sudo tailscaled ${TS_DAEMON_FLAGS}
priority=3
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:tailscale-up]
command=bash -c 'sleep 5 && echo "tailscale-up: running tailscale up..." && sudo tailscale up --authkey=%(ENV_TS_AUTHKEY)s ${TS_UP_FLAGS} && echo "tailscale-up: connected successfully"'
priority=4
startsecs=0
autorestart=unexpected
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
TAILSCALE

  if [ "$TAILSCALE_SERVE_ENABLED" = "true" ]; then
    cat >> /tmp/supervisord.conf << TSSERVE

[program:tailscale-serve]
command=bash -c 'sleep 10 && echo "tailscale-serve: running tailscale serve..." && sudo tailscale serve --bg http://localhost:${TAILSCALE_SERVE_PORT} && echo "tailscale-serve: serve configured successfully"'
priority=5
startsecs=0
autorestart=unexpected
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
TSSERVE
  fi
fi

exec supervisord -n -c /tmp/supervisord.conf
