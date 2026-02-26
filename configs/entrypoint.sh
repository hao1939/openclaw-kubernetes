#!/bin/bash
set -e

DISPLAY_NUM=${DISPLAY_NUM:-99}
SCREEN_RES=${SCREEN_RESOLUTION:-1920x1080x24}
VNC_PORT=${VNC_PORT:-5900}
NOVNC_PORT=${NOVNC_PORT:-6080}

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

exec supervisord -n -c /tmp/supervisord.conf
