#!/bin/bash
clear


# Define SSH config path
SSH_CONFIG="$HOME/.ssh/config"


# === Resource preference file ===
CONFIG_DIR="$HOME/.config/greene"
PREFS_FILE="$CONFIG_DIR/last_job_prefs"
mkdir -p "$CONFIG_DIR"

# Hardcoded fallbacks
DEFAULT_TIME_HOURS=1
DEFAULT_PARTITION="short"
DEFAULT_CPUS=4
DEFAULT_RAM=16G
DEFAULT_GPU=no
DEFAULT_REMOTE_PORT=8888
DEFAULT_LOCAL_PORT=8888
DEFAULT_OVERLAY_PATH="/scratch/edk202/word2gm_ol/overlay-15GB-500K.ext3"
DEFAULT_CONTAINER_PATH="/scratch/work/public/singularity/cuda12.6.3-cudnn9.5.1-ubuntu22.04.5.sif"
DEFAULT_CONDA_ENV="word2gm-fast2"

# Load previous values
if [[ -f "$PREFS_FILE" ]]; then
  source "$PREFS_FILE"
fi

# Fall back to hardcoded defaults
TIME_HOURS="${TIME_HOURS:-$DEFAULT_TIME_HOURS}"
PARTITION="${PARTITION:-$DEFAULT_PARTITION}"
CPUS="${CPUS:-$DEFAULT_CPUS}"
RAM="${RAM:-$DEFAULT_RAM}"
GPU="${GPU:-$DEFAULT_GPU}"
REMOTE_PORT="${REMOTE_PORT:-$DEFAULT_REMOTE_PORT}"
LOCAL_PORT="${LOCAL_PORT:-$DEFAULT_LOCAL_PORT}"
OVERLAY_PATH="${OVERLAY_PATH:-$DEFAULT_OVERLAY_PATH}"
CONTAINER_PATH="${CONTAINER_PATH:-$DEFAULT_CONTAINER_PATH}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-$DEFAULT_CONDA_ENV}"


# === Prompt for resource preferences ===
read -p "⏱  Job duration in hours [1–24+] (default: ${TIME_HOURS:-1}): " input_time
read -p "📊 Slurm partition (default: $PARTITION): " input_partition
read -p "🧠 Number of CPUs [1–14] (default: $CPUS): " input_cpus
read -p "🧠 RAM [1,2,4,8,16,32,64,96,128G] (default: $RAM): " input_ram
read -p "🧠 GPU? [yes/no] (default: $GPU): " input_gpu
read -p "🔌 Remote port for Jupyter (default: $REMOTE_PORT): " input_remote
read -p "🔌 Local port to access it (default: $LOCAL_PORT): " input_local
read -p "📂 Overlay path (default: $OVERLAY_PATH): " input_overlay
read -p "📦 Container path (default: $CONTAINER_PATH): " input_container
read -p "🧪 Conda environment name (default: $CONDA_ENV_NAME): " input_env

# Apply only if user gave input
[[ -n "$input_time" ]] && TIME_HOURS="$input_time"
[[ -n "$input_partition" ]] && PARTITION="$input_partition"
[[ -n "$input_cpus" ]] && CPUS="$input_cpus"
[[ -n "$input_ram" ]] && RAM="$input_ram"
[[ -n "$input_gpu" ]] && GPU="$input_gpu"
[[ -n "$input_remote" ]] && REMOTE_PORT="$input_remote"
[[ -n "$input_local" ]] && LOCAL_PORT="$input_local"
[[ -n "$input_overlay" ]] && OVERLAY_PATH="$input_overlay"
[[ -n "$input_container" ]] && CONTAINER_PATH="$input_container"
[[ -n "$input_env" ]] && CONDA_ENV_NAME="$input_env"

# Save for next session
cat > "$PREFS_FILE" <<EOF
TIME_HOURS=$TIME_HOURS
PARTITION=$PARTITION
CPUS=$CPUS
RAM=$RAM
GPU=$GPU
REMOTE_PORT=$REMOTE_PORT
LOCAL_PORT=$LOCAL_PORT
OVERLAY_PATH="$OVERLAY_PATH"
CONTAINER_PATH="$CONTAINER_PATH"
CONDA_ENV_NAME="$CONDA_ENV_NAME"
EOF


# === Convert RAM to Slurm format ===
RAM_MB=$(( $RAM * 1000 ))


# === Print summary of selected resources ===
echo
echo -e "\n🔧 \033[1mSelected resources:\033[0m"
echo -e "⏱  Job duration: \033[1m${TIME_HOURS} hours\033[0m"
echo -e "📊 Slurm partition: \033[1m$PARTITION\033[0m"
echo -e "🧠 Number of CPUs: \033[1m$CPUS\033[0m"
echo -e "🧠 RAM: \033[1m$RAM_MB MB\033[0m"
echo -e "🧠 GPU: \033[1m$GPU\033[0m"
echo -e "🔌 Remote port for Jupyter: \033[1m$REMOTE_PORT\033[0m"
echo -e "🔌 Local port to access it: \033[1m$LOCAL_PORT\033[0m"
echo -e "📂 Overlay path: \033[1m$OVERLAY_PATH\033[0m"
echo -e "📦 Container path: \033[1m$CONTAINER_PATH\033[0m"
echo -e "🧪 Conda environment name: \033[1m$CONDA_ENV_NAME\033[0m"
echo


echo -e "🚀 \033[1mRUNNING!\033[0m"


# === Step 0: Cancel leftover jobs and tunnels ===
echo -e "🧹 Cleaning up any leftover compute jobs and tunnels..."

ssh greene-login "scancel -u \$USER || true"
lsof -i tcp:${LOCAL_PORT} | grep ssh | awk '{print $2}' | xargs -r kill -9


# === Step 1: Create and upload launcher script ===

echo -e "📄 Uploading Jupyter launcher script..."

ssh greene-login "mkdir -p \$HOME/.config/greene && cat > \$HOME/.config/greene/launch_jupyter.sh" <<EOF
#!/bin/bash

source /ext3/env.sh
conda activate ${CONDA_ENV_NAME}
pip install --quiet ipykernel
python -m ipykernel install --user \
  --name ${CONDA_ENV_NAME} \
  --display-name "Remote kernel: ${CONDA_ENV_NAME}"
jupyter lab --no-browser --port=8888 --ip=0.0.0.0 --ServerApp.token=''
EOF

ssh greene-login "chmod +x \$HOME/.config/greene/launch_jupyter.sh"


# === Step 2: Create and upload the entrypoint script ===

echo -e "📄 Uploading entrypoint script..."

ssh greene-login "mkdir -p \$HOME/.config/greene && cat > \$HOME/.config/greene/compute_entrypoint.sh" <<EOF
#!/bin/bash

/usr/bin/hostname > \$HOME/.config/greene/last_node.txt
EOF

ssh greene-login "chmod +x \$HOME/.config/greene/compute_entrypoint.sh"


# === Step 3: SSH into Greene, launch compute node, write hostname ===

echo -e "🚀 Launching compute node on Greene..."

ssh greene-login "
  export OVERLAY_PATH='$OVERLAY_PATH'
  export CONTAINER_PATH='$CONTAINER_PATH'

  nohup srun \
     --time=${TIME_HOURS}:00:00 \
     --partition=$PARTITION \
     --cpus-per-task=$CPUS \
     --mem=$RAM_MB \
     $([[ "$GPU" == "yes" ]] && echo "--gres=gpu:1") \
     bash -c '
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
    echo -e "📎 Compute node assigned: $HOSTNAME"
    break
  fi
  sleep 1
done

if [[ -z "$HOSTNAME" ]]; then
  echo -e "❌ Timed out waiting for compute node assignment."
  exit 1
fi

ssh greene-login "rm -f .config/greene/last_node.txt"


# === Step 5: Update local SSH config ===

echo -e "🛠  Updating ~/.ssh/config: greene-compute → $HOSTNAME"

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


# === Step 6: Forward port from compute node to local ===

sleep 20

echo -e "🔁 Forwarding localhost:$LOCAL_PORT to $HOSTNAME:$REMOTE_PORT via greene-compute"
echo -e "🌐 Access the forwarded port at: http://127.0.0.1:$LOCAL_PORT/lab"

# Wait until Slurm confirms the node is ready
until ssh -o ConnectTimeout=2 greene-compute 'true' 2>/dev/null; do
    echo "⏳ Waiting for greene-compute to accept SSH..."
    sleep 3
done

# Now forward
ssh -N -L $LOCAL_PORT:localhost:$REMOTE_PORT greene-compute
