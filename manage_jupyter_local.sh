#!/bin/bash
set -e

# ==== CONFIG ====
SINGULARITY_IMAGE="/scratch/work/public/singularity/cuda12.6.3-cudnn9.5.1-ubuntu22.04.5.sif"
OVERLAY="/scratch/edk202/word2gm_ol/overlay-15GB-500K.ext3"
ENV_NAME="word2gm-fast2"
PORT=8888
PARTITION="short"
REMOTE_SCRIPT="$HOME/bin/jupyter_greene.sh"
REMOTE_LOG="$HOME/.jupyter/jupyter.log"
TUNNEL_PIDFILE="/tmp/ssh_tunnel_${PORT}.pid"
REMOTE_USER="edk202"
LOGIN_NODE="greene.hpc.nyu.edu"

# ==== USAGE ====
if [[ "$1" == "--stop" ]]; then
  echo "🛑 Stopping remote Jupyter session..."
  ssh "$REMOTE_USER@$LOGIN_NODE" "$REMOTE_SCRIPT --stop" || true
  if [[ -f "$TUNNEL_PIDFILE" ]]; then
    PID=$(cat "$TUNNEL_PIDFILE")
    echo "🧹 Killing local SSH tunnel on port $PORT (PID $PID)..."
    kill "$PID" || true
    rm -f "$TUNNEL_PIDFILE"
  fi
  exit 0
fi

if [[ "$1" != "--start" ]]; then
  echo "Usage: $0 --start | --stop"
  exit 1
fi

# ==== START JUPYTER ====
echo "🧹 Killing any local SSH tunnels on port $PORT..."
fuser -k "$PORT"/tcp 2>/dev/null || echo "⚠️ No existing tunnel on port $PORT"

echo "🚀 Launching Jupyter on a dynamic compute node..."
ssh "$REMOTE_USER@$LOGIN_NODE" "$REMOTE_SCRIPT --start" &

echo "⏳ Waiting for remote URL and node..."
for i in {1..30}; do
  sleep 2
  NODE=$(ssh "$REMOTE_USER@$LOGIN_NODE" "grep '^NODE=' $REMOTE_LOG | tail -1 | cut -d= -f2")
  URL=$(ssh "$REMOTE_USER@$LOGIN_NODE" "grep -oE 'http://[^ ]+:${PORT}/lab\\?token=[^[:space:]]+' $REMOTE_LOG | head -1")
  if [[ -n "$NODE" && -n "$URL" ]]; then
    break
  fi
done

if [[ -z "$NODE" || -z "$URL" ]]; then
  echo "❌ Failed to extract compute node or Jupyter URL."
  exit 1
fi

# ==== SET UP TUNNEL ====
echo "🔗 Starting SSH tunnel to $NODE via $LOGIN_NODE..."
ssh -N -f -L "$PORT:$NODE:$PORT" -J "$REMOTE_USER@$LOGIN_NODE" "$REMOTE_USER@$NODE"
echo $! > "$TUNNEL_PIDFILE"
echo "🌐 Open this URL in your browser:"
echo "$URL"
