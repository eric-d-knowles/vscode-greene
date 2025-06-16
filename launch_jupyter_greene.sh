#!/bin/bash


# === Default values ===
REMOTE_PORT=8888
LOCAL_PORT=8888


# === Parse CLI arguments ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-port)
      REMOTE_PORT="$2"
      shift 2
      ;;
    --local-port)
      LOCAL_PORT="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--remote-port PORT] [--local-port PORT]"
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $1"
      echo "Usage: $0 [--remote-port PORT] [--local-port PORT]"
      exit 1
      ;;
  esac
done


# === Configuration ===
SSH_CONFIG="$HOME/.ssh/config"
OVERLAY_PATH="/scratch/\$USER/word2gm_ol/overlay-15GB-500K.ext3"
CONTAINER_PATH="/scratch/work/public/singularity/cuda12.6.3-cudnn9.5.1-ubuntu22.04.5.sif"
CONDA_ENV_NAME="word2gm-fast2"


# === Step 0: Cancel leftover jobs and tunnels ===
echo -e "🧹 \033[1mCleaning up any leftover compute jobs and tunnels...\033[0m"

ssh greene-login "scancel -u \$USER || true"
lsof -i tcp:${LOCAL_PORT} | grep ssh | awk '{print $2}' | xargs -r kill -9


# === Step 1: Create and upload launcher script ===

echo -e "📄 \033[1mUploading Jupyter launcher script... \033[0m"

ssh greene-login "mkdir -p \$HOME/.config/greene && cat > \$HOME/.config/greene/launch_jupyter.sh" <<EOF
#!/bin/bash

source /ext3/env.sh
conda activate ${CONDA_ENV_NAME}
pip install --quiet ipykernel
python -m ipykernel install --user \
  --name ${CONDA_ENV_NAME} \
  --display-name "Remote kernel: ${CONDA_ENV_NAME}"
jupyter lab --no-browser --port=8888 --ip=0.0.0.0 --NotebookApp.token=''
EOF

ssh greene-login "chmod +x \$HOME/.config/greene/launch_jupyter.sh"


# === Step 2: Create and upload the entrypoint script ===

echo -e "📄 \033[1mUploading entrypoint script...\033[0m"

ssh greene-login "mkdir -p \$HOME/.config/greene && cat > \$HOME/.config/greene/compute_entrypoint.sh" <<EOF
#!/bin/bash

/usr/bin/hostname > \$HOME/.config/greene/last_node.txt
EOF

ssh greene-login "chmod +x \$HOME/.config/greene/compute_entrypoint.sh"


# === Step 3: SSH into Greene, launch compute node, write hostname ===

echo -e "🚀 \033[1mLaunching compute node on Greene...\033[0m"

ssh greene-login "
  export OVERLAY_PATH='$OVERLAY_PATH'
  export CONTAINER_PATH='$CONTAINER_PATH'

  nohup srun --time=1:00:00 --partition=short bash -c '
    singularity exec --overlay \$OVERLAY_PATH:rw \$CONTAINER_PATH bash -c \"
      bash \$HOME/.config/greene/compute_entrypoint.sh;
      nohup bash \$HOME/.config/greene/launch_jupyter.sh > \$HOME/.jupyter/jlab.log 2>&1 &
      sleep infinity
    \"
  ' > \$HOME/.jupyter/srun_debug.log 2>&1 &
  disown
"


# === Step 4: Poll for compute node hostname ===

for i in {1..30}; do
  HOSTNAME=$(ssh greene-login "cat .config/greene/last_node.txt 2>/dev/null" || true)
  if [[ -n "$HOSTNAME" ]]; then
    echo -e "📎 \033[1mCompute node assigned: $HOSTNAME\033[0m"
    break
  fi
  sleep 1
done

if [[ -z "$HOSTNAME" ]]; then
  echo -e "❌ \033[1mTimed out waiting for compute node assignment.\033[0m"
  exit 1
fi

ssh greene-login "rm -f .config/greene/last_node.txt"


# === Step 5: Update local SSH config ===

echo -e "🛠  \033[1mUpdating ~/.ssh/config: greene-compute → $HOSTNAME\033[0m"

awk -v nh="$HOSTNAME" '
/^Host greene-compute$/ {
    print; in_block=1; found=0; next
}
in_block && /^Host / {
    if (!found) print "  HostName " nh
    in_block=0
}
in_block && /^ *HostName / {
    $0 = "  HostName " nh
    found=1
}
{print}
END {
    if (in_block && !found) print "  HostName " nh
}
' "$SSH_CONFIG" > "${SSH_CONFIG}.tmp" && mv "${SSH_CONFIG}.tmp" "$SSH_CONFIG"


# === Step 6: Forward port 8888 from compute node to local ===

sleep 20

echo -e "🔁 \033[1mForwarding localhost:$LOCAL_PORT to $HOSTNAME:$REMOTE_PORT via greene-compute\033[0m"
echo -e "🌐 \033[1mAccess the forwarded port at: http://127.0.0.1:$LOCAL_PORT\033[0m"

# Wait until Slurm confirms the node is ready
until ssh -o ConnectTimeout=2 greene-compute 'true' 2>/dev/null; do
    echo "⏳ Waiting for greene-compute to accept SSH..."
    sleep 3
done

# Now forward
ssh -N -L $LOCAL_PORT:localhost:$REMOTE_PORT greene-compute
