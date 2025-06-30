#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

clear



# --- Set Pushover User Key ---
export PUSHOVER_USER_KEY="uoq9wixd1ww2no8vem1kwnezhkd6cn"

# --- Set Pushover API Token ---
export PUSHOVER_API_TOKEN="adk7vvca5hdn5u2q7sksqaziv1pdqo"



# --- Pushover notification function ---
pushover_notify() {
    local message="$1"
    if [[ -z "${PUSHOVER_USER_KEY:-}" || -z "${PUSHOVER_API_TOKEN:-}" ]]; then
        printf '\033[1;31m[Pushover] PUSHOVER_USER_KEY or PUSHOVER_API_TOKEN not set. Skipping notification.\033[0m\n'
        return
    fi
    curl -s --form-string "token=$PUSHOVER_API_TOKEN" \
         --form-string "user=$PUSHOVER_USER_KEY" \
         --form-string "message=$message" \
         https://api.pushover.net/1/messages.json > /dev/null || \
         printf '\033[1;31m[Pushover] Failed to send notification.\033[0m\n'
}




# --- Cleanup on abort ---
cleanup() {
    printf '\033[1;31m\nAborted. Cleaning up jobs on greene-login...\033[0m\n'
    ssh greene-login 'scancel -u $USER || true'
    lsof -i tcp:${LOCAL_PORT} | grep ssh | awk '{print $2}' | xargs -r kill -9 || true
    exit 1
}
trap cleanup INT TERM



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
    # shellcheck source=/dev/null
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
printf '\033[1;34mPlease specify your Greene-compute resource request:\033[0m\n'
read -p "Job duration in hours (default: ${TIME_HOURS:-1}): " input_time
read -p "Slurm partition [eg: short, rtx8000, any] (default: $PARTITION): " input_partition
read -p "Number of CPUs [1–14] (default: $CPUS): " input_cpus
read -p "RAM [GBs] (default: $RAM): " input_ram
read -p "GPU? [yes/no] (default: $GPU): " input_gpu
read -p "Remote port for Jupyter (default: $REMOTE_PORT): " input_remote
read -p "Local port to access it (default: $LOCAL_PORT): " input_local
read -p "Overlay path (default: $OVERLAY_PATH): " input_overlay
read -p "Container path (default: $CONTAINER_PATH): " input_container
read -p "Conda environment name (default: $CONDA_ENV_NAME): " input_env
printf '\n'


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


# Convert RAM to SLURM format
RAM_NUM=$(echo "$RAM" | sed 's/[Gg]//')
RAM_MB=$(( RAM_NUM * 1000 ))



# === Prepare request ===
printf '\033[1;31mPreparing request...\033[0m\n'

# Cancel leftover jobs and tunnels
printf 'Cleaning up any leftover compute jobs and tunnels\n'
ssh greene-login "scancel -u \$USER || true"
lsof -i tcp:${LOCAL_PORT} | grep ssh | awk '{print $2}' | xargs -r kill -9 || true

# Create and upload launcher script
printf 'Uploading Jupyter launcher script\n'

ssh greene-login "mkdir -p \$HOME/.config/greene && cat > \$HOME/.config/greene/launch_jupyter.sh" <<EOF
#!/bin/bash

source /ext3/env.sh
conda activate ${CONDA_ENV_NAME}
if ! python -c 'import ipykernel' 2>/dev/null; then
  pip install --quiet ipykernel
fi
python -m ipykernel install --user \
  --name ${CONDA_ENV_NAME} \
  --display-name "Remote kernel: ${CONDA_ENV_NAME}"
jupyter lab --no-browser --port=8888 --ip=0.0.0.0 --ServerApp.token=''
EOF

ssh greene-login "chmod +x \$HOME/.config/greene/launch_jupyter.sh"


# Create and upload the entrypoint script
printf 'Uploading entrypoint script\n'
printf '\n'



ssh greene-login "mkdir -p \$HOME/.config/greene && cat > \$HOME/.config/greene/job_script.sh" <<'EOF'
#!/bin/bash

cleanup_remote() {
    bash $HOME/.config/greene/cleanup_greene.sh $USER $LOCAL_PORT
}
trap cleanup_remote INT TERM EXIT

/usr/bin/hostname > $HOME/.config/greene/last_node.txt
nohup bash $HOME/.config/greene/launch_jupyter.sh > $HOME/.jupyter/jlab.log 2>&1 &
sleep infinity
EOF

ssh greene-login "chmod +x \$HOME/.config/greene/job_script.sh"


# === Submit request ===
printf '\033[1;31mSubmitting request...\033[0m\n'

pushover_notify "[Greene] Jupyter request submitted. Waiting for compute node..."

# SSH into Greene, launch compute node, write hostname
ssh greene-login "
  export OVERLAY_PATH='$OVERLAY_PATH'
  export CONTAINER_PATH='$CONTAINER_PATH'

  nohup srun \
     --time=${TIME_HOURS}:00:00 \
     $([[ \"$PARTITION\" != \"any\" ]] && echo \"--partition=$PARTITION\") \
     --cpus-per-task=$CPUS \
     --mem=$RAM_MB \
     $([[ \"$GPU\" == \"yes\" ]] && echo \"--gres=gpu:1\") \
     singularity exec --overlay \$OVERLAY_PATH:rw $([[ \"$GPU\" == \"yes\" ]] && echo \"--nv\") \$CONTAINER_PATH bash \$HOME/.config/greene/job_script.sh \
     > \$HOME/.jupyter/srun_debug.log 2>&1 &
  disown
"

# Poll for compute node hostname
for i in {1..3600}; do
  HOSTNAME=$(ssh greene-login "cat .config/greene/last_node.txt 2>/dev/null" || true)
  if [[ -n "$HOSTNAME" ]]; then
    printf '\033[1;31mRequest granted!\033[0m\n'
    printf '\n'
    break
  fi
  sleep 1
done

if [[ -z "$HOSTNAME" ]]; then
  printf '❌ Timed out waiting for compute node assignment.\n'
  exit 1
fi

printf '\033[1;34mConnection info:\033[0m\n'  
printf 'Node assigned: \033[1;33m%s\033[0m\n' "$HOSTNAME"
ssh greene-login "rm -f .config/greene/last_node.txt"

#  Update local SSH config
printf 'Updating SSH config file\n'

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

# Forward port from compute node to local
sleep 20

# Wait until Slurm confirms the node is ready
until ssh -o ConnectTimeout=2 greene-compute 'true' 2>/dev/null; do
    printf 'Waiting for greene-compute to accept SSH...\n'
    sleep 3
done

# Now forward (background subprocess)
printf 'Forwarding local port\n'
ssh -N -L $LOCAL_PORT:localhost:$REMOTE_PORT greene-compute &
PORT_FORWARD_PID=$!

# Print access info and send notification after port forward starts
printf 'Access Jupyter kernel: \033[1;33mhttp://127.0.0.1:%s/lab\033[0m\n' "$LOCAL_PORT"
printf '\n'

pushover_notify "[Greene] Jupyter request granted! Node: $HOSTNAME"
