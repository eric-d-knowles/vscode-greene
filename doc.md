# Remote Development on NYU HPC’s Greene Cluster

New York University’s High-Performance Computing (HPC) facility offers browser-based access to Jupyter Notebook, JupyterLab, and other applications through the [OnDemand service](https://sites.google.com/nyu.edu/nyu-hpc/accessing-hpc#h.7kawz2pfzl9d). With OnDemand, you run Jupyter notebooks on a remote server rather than on your personal computer. The computations take place on NYU’s HPC infrastructure, while you interact with the notebooks through your web browser.

This approach to code development offers many advantages, including seamless access to Greene’s full range of [computing resources](https://www.nyu.edu/research/navigating-research-technology/nyu-greene.html). Nevertheless, browser-based coding has downsides. OnDemand limits users’ choice of computing environments and restricts the installation of smart coding tools like AI-assisted code completion and AI copilots.

For users who want more flexibility, there are benefits to coding in a fully featured and extensible _local_ Integrated Development Environment (IDE) such as [Visual Studio Code](https://code.visualstudio.com) (VS Code). VS Code allows you to edit Jupyter notebooks outside of the traditional Jupyter ecosystem.

Fortunately, moving code development to your personal laptop or desktop does not mean giving up direct access to Greene’s computing resources. By linking a local IDE to the Greene cluster, you can take advantage of advanced tools and extensions — including AI features — while still running your code on powerful remote hardware.

This guide walks through the process of configuring VS Code to connect to Greene, affording you full control over your development environment without sacrificing computational power.

Note that the guide assumes familiarity with Singularity containers and conda environments — NYU HPC’s recommended approach to creating independent and [reproducible](https://guides.nyu.edu/software-reproducibility/using-containers-and-reproducibility-tools) computing environments. If you’re new to this approach, start [here](https://sites.google.com/nyu.edu/nyu-hpc/hpc-systems/greene/software/singularity-with-miniconda) to learn how to create a writable container overlay, install Miniforge, and configure a conda environment inside the container. If you’re interested in using your Singularity setup with the OnDemand web interface, [this guide](https://sites.google.com/nyu.edu/nyu-hpc/hpc-systems/greene/software/open-ondemand-ood-with-condasingularity) covers that process.

## Steps to Link VS Code to a Greene Compute Node

1. **Connect to NYU-NET**

    You’ll need to be on NYU’s network ([NYU-NET](https://www.nyu.edu/life/information-technology/infrastructure/network-services/nyu-net.html)). If you’re on a campus wired or WiFi connection, you’re on NYU-NET already. If you’re off campus, you must connect through NYU’s VPN using the [Cisco AnyConnect software client](https://www.nyu.edu/life/information-technology/infrastructure/network-services/vpn.html).

2. **Configure SSH**

    Set up a Secure Shell (SSH) configuration on your local machine by adding the entries below to your `~/.ssh/config` file. Don’t forget to replace `<NetID>` with your actual NetID.
    
    On a Mac, `config` can be easily located by clicking **Go > Go to Folder (⇧⌘G)** from the menu bar and typing `~/.ssh/` in the dialog box. Press Enter to open the folder. Double-click `config` to open it in TextEdit.

    In Windows, `config` can be found by pressing `Win + R` and typing `%USERPROFILE%\.ssh` in the dialog box and hitting Enter. Right-click on `config`, choose **Open with**, and select a text editor (e.g., Notepad).

    ```
    Host greene-login
    HostName greene.hpc.nyu.edu
    User <NetID> 
    StrictHostKeyChecking no
    ServerAliveInterval 60
    ForwardAgent yes
    IdentitiesOnly yes
    IdentityFile ~/.ssh/id_ed25519
    UserKnownHostsFile /dev/null
    LogLevel ERROR

    Host greene-compute
    HostName <ComputeNode>
    User <NetID>
    ProxyJump greene-login
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    ```

    The `greene-login` entry uses SSH keys to simplify connection to the Greene login node and avoid repeated password prompts. If you don’t already have an SSH key pair (`id_ed25519`), you can generate one by running `ssh-keygen -t ed25519` in a Terminal window connected to your local machine. Then copy your public key to the login server by running `ssh-copy-id <NetID>@greene.hpc.nyu.edu` (replacing `<NetID>` as appropriate).

    Because CPU-heavy code should never be run on a login node, we’re going to request resources on a compute node. The SSH configuration file’s `greene-compute` entry makes it easy to connect to that node once it’s assigned. You’ll update the placeholder (`<ComputeNode>`) later to match the node you’ve been allocated.

3. **Connect to a Greene Login Node**

    Open a Terminal window on your local machine and connect to the Greene login node using the SSH alias you configured earlier:

    ```
    ssh greene-login
    ```

4. **Request Resources on a Compute Node**

    After logging in to the Greene cluster, you’ll need to request an interactive session on a compute node — a dedicated machine where your code will run. In your terminal (still connected to `greene-login`), cut and paste this:

    ```
    srun --partition=short --pty --gres=gpu:0 --mem=32G --cpus-per-task=4 --time=01:00:00 bash
    ```

    This command requests:
    * `partition=short` – a short-duration partition
    * `pty` – an interactive shell session
    * `gres=gpu:0` – no GPU (set to 1 if you need one)
    * `mem=32G` – 32 gigabytes of RAM
    * `cpus-per-task=4` – 4 CPU cores
    * `time=01:00:00` – a maximum runtime of 1 hour

    You can change the flags in this command to request more time, memory, CPUs, or a GPU.
    
    After resources are allocated (which can take time), you’ll be dropped into a shell on one of Greene’s compute nodes. To confirm the name of your assigned node, you can run `hostname` at your Terminal prompt. You’ll see something like `cm026.hpc.nyu.edu`.

5. **Edit Your SSH Configuration to Reference Your Assigned Compute Node**

    Next, edit your `~/.ssh/config` file to specify the compute node you’ve been assigned. For example, if you are allocated `cm026.hpc.nyu.edu`, swap the `<ComputeNode>` placeholder with `cm026.hpc.nyu.edu`.
    
    **Note:** You can either edit your SSH configuration file through your local operating system (e.g., macOS or Windows) or through the Terminal. If you wish to edit `~/.ssh/config` in the Terminal using `vim` or `nano` (or another editor), be sure to open a _new Terminal window_. This file lives on your local machine and you won’t be able to find it through the compute node window opened in the last step.

    **Optional update code**: To make updating the `greene-compute` HostName easier, run this code in a _local_ Terminal window:

    ```
    echo -n "Enter new HostName for greene-compute: "
    read newhost && awk -v nh="$newhost" '
    /^Host greene-compute$/ {print; in_block=1; found=0; next}
    in_block && /^Host / {
        if (!found) print "  HostName " nh;
        in_block=0
    }
    in_block && /^ *HostName / {
        $0 = "  HostName " nh;
        found=1
    }
    {print}
    END {
        if (in_block && !found) print "  HostName " nh
    }
    ' ~/.ssh/config > ~/.ssh/config.tmp && mv ~/.ssh/config.tmp ~/.ssh/config
    ```

6. **Launch a JupyterLab Server Within a Containerized Conda Environment**

    This step launches your Conda environment inside a Singularity container and starts a JupyterLab server there. The command below mounts your writable overlay, activates the specified Conda environment inside the container, and starts the server. The Jupyter server acts as a bridge between VS Code and the remote Python kernel running inside the Singularity container.

    Update the configuration variables to reflect your own file paths and environment name, then paste and run the code in the compute node you were dropped into in the last step.

    ```
    # Configuration
    OVERLAY_PATH="/scratch/${USER}/word2gm_ol/overlay-15GB-500K.ext3"
    CONTAINER_PATH="/scratch/work/public/singularity/cuda12.6.3-cudnn9.5.1-ubuntu22.04.5.sif"
    CONDA_ENV_NAME="word2gm-fast2"

    # Jupyter cleanup
    echo "Cleaning up stale Jupyter runtime files..."
    rm -f ~/.local/share/jupyter/runtime/nbserver-*.json
    rm -f ~/.local/share/jupyter/runtime/kernel-*.json

    # Kill any lingering jupyter servers
    if pgrep -u "$USER" -f "jupyter-lab" > /dev/null; then
        echo "Killing old JupyterLab processes..."
        pkill -u "$USER" -f "jupyter-lab"
    fi

    # Run Singularity command
    singularity exec \
    --overlay "${OVERLAY_PATH}:rw" \
    "${CONTAINER_PATH}" \
    bash -c "
        source /ext3/env.sh
        conda activate \"${CONDA_ENV_NAME}\"
        pip install --quiet ipykernel
        python -m ipykernel install --user \
        --name \"${CONDA_ENV_NAME}\" \
        --display-name \"Remote kernel: ${CONDA_ENV_NAME}\"
        jupyter lab --no-browser --port=8888 --ip=0.0.0.0
    "
    ```

    This code first cleans up any stale Jupyter files and server processes leftover from a previous session. Then, we run several commands inside your Singularity container:
    * `source /ext3/env.sh` initializes conda within your container
    * `conda activate \"${CONDA_ENV_NAME}\"` starts the environment for your project
    * `pip install --quiet ipykernel` installs the [IPython kernel](https://ipython.readthedocs.io/en/stable/install/kernel_install.html) if needed
    * `python -m ipykernel install [...]` registers a new `ipykernel`
    * `jupyter [...]` starts a Jupyter server inside the container

7. **Get Port Number and URL from Jupyter Server Output**

    Output from the `jupyter` command should appear in the Terminal. The crucial part will look similar to this:

    ```
    To access the server, open this file in a browser:
        file:///home/edk202/.local/share/jupyter/runtime/jpserver-2205529-open.html
    Or copy and paste one of these URLs:
        http://cm005.hpc.nyu.edu:8888/lab?token=33d4b561e076e9bdc765dd2acc16b7fc00e431954b6bc5ad
        http://127.0.0.1:8888/lab?token=33d4b561e076e9bdc765dd2acc16b7fc00e431954b6bc5ad
    ```

    The last line is what we need. We’ll use the URL as a whole to access the Jupyter server in VS Code. But before that, we need to ensure that your local machine is listening to the compute node on the right port. That port is listed after the colon in the first part of the URL — in this example `8888`.

8. **Forward the Local Port to the Remote Port**

    You must now forward local port `8888` to the remote port you find in the Jupyter URL. This provides a secure way for your local machine to listen to the Jupyter server you just launched inside the remote container.

    If the remote port is `8889`, you would use this command to get your local machine to listen to the compute node:

    ```
    ssh -f -N -L 8888:localhost:8889 greene-compute
    ```
    
    **Note:** This command needs to be executed on your local machine, so be sure to run it in a new Terminal window; it won’t work in the compute node window.

9. **Activate the Kernel in VS Code**

    The final step is to open VS Code and access the Jupyter server you’ve just set up. Here's what to do:
    
    - Open VS Code on your computer and click the Search box at the top of the VS Code window.
    - Click the **Show and Run Commands** option. In the Search box, start typing `Jupyter: Clear`. The option `Jupyter: Clear Jupyter Remote Server List` should appear at the top of the list; click it. This will clean up any stale servers from VS Code's menu cache.
    - Select **File > New File > Jupyter Notebook**. This will open an untitled notebook.
    - In the upper-right corner of the notebook, click **Select Kernel > Existing Jupyter Server**.
    - Paste in the URL from the Jupyter server output in the compute-node Terminal window. Be sure to copy the one that contains `127.0.0.1` — not the one with a resolved hostname (e.g., `cm026.hpc.nyu.edu`) in it.
    - Hit enter to connect to your running Jupyter server.

If all goes well, you should now be able to write code in a local instance of VS Code while accessing all the resources you've requested on Greene's compute node!

## Automating the Entire Process

It can be helpful to walk through the steps above a few times, as they exemplify how to interact with NYU's Greene cluster from your personal machine. If you code often in VS Code, however, the manual approach is bound to get tedious. The following script aims to automate the entire process.

**Note:** The script isn't fully tested and isn't guaranteed to work on every system without tweaks.

To use the script, you must:

1. Be on NYU-NET.
2. Have a `~/.ssh/config` file containing the entries shown above.
3. Save the script somewhere on your computer (e.g., in `~/code` or `~/scripts`). Paste the code into a text editor and save it in your preferred folder as `launch_jupyter_greene.sh`.
4. Give the script execute permission. Open a Terminal window, navigate to the folder containing the script, and run `chmod +x launch_jupyter_greene.sh`.

At this point, you can run the script to set up a connection to a Greene compute node by typing `./launch_jupyter_greene.sh`. You'll be prompted for several options (including the locations of your Singularity container and overlay file and the resources you are requesting). If all goes well, your output will include a line similar to this:

    🌐 Access the forwarded port at: http://127.0.0.1:8888/lab

Now, you can open a notebook in VS Code and make this your kernel path.

### `launch_jupyter_greene.sh`

```
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
```
