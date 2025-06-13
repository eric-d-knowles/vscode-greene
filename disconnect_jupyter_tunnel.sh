#!/bin/bash

if [ -f /tmp/jupyter_ssh_tunnel.pid ]; then
    PID=$(cat /tmp/jupyter_ssh_tunnel.pid)
    echo "🧹 Killing SSH tunnel (PID $PID)..."
    kill $PID && rm /tmp/jupyter_ssh_tunnel.pid
    echo "✅ Tunnel closed."
else
    echo "⚠️ No tunnel PID found. Is the tunnel already closed?"
fi
