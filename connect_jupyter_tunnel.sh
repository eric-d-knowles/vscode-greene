#!/bin/bash

PORT=8888
REMOTE_ALIAS="greene-login"

echo "🔍 Checking if SSH tunnel to port $PORT is already running..."

if lsof -i tcp:$PORT | grep ssh > /dev/null; then
    echo "✅ SSH tunnel is already active on port $PORT"
else
    echo "🔗 Launching SSH tunnel to $REMOTE_ALIAS..."
    ssh -N -L ${PORT}:localhost:${PORT} ${REMOTE_ALIAS} &
    TUNNEL_PID=$!
    echo "🚀 Tunnel started (PID $TUNNEL_PID)"
    # Optional: Save the PID to a file for later cleanup
    echo $TUNNEL_PID > /tmp/jupyter_ssh_tunnel.pid
fi

echo ""
echo "🌐 Visit the following URL in your browser:"
echo "👉 http://localhost:${PORT}/lab"