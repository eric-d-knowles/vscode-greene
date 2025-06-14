# Remote Development on NYU HPC’s Greene Cluster

New York University’s High-Performance Computing (HPC) facility offers browser-based access to Jupyter Notebook, Jupyter Lab, and other applications through the [OnDemand service](https://sites.google.com/nyu.edu/nyu-hpc/accessing-hpc#h.7kawz2pfzl9d). With OnDemand, you run Jupyter notebooks on a remote server rather than on your personal computer. The computations take place on NYU's HPC infrastructure, while you interact with the notebooks through your web browser.

This approach to code development offers many advantages, including seamless access to Greene‘s full range of [computing resources](https://www.nyu.edu/research/navigating-research-technology/nyu-greene.html). Nevertheless, browser-based coding has downsides. OnDemand limits users‘ choice of computing environments and restricts the installation of smart coding tools like AI-assisted code completion and AI copilots.

For users who want more flexibility, there are benefits to coding in a fully featured and extensible _local_ Integrated Development Environment (IDE) such as [Visual Studio Code](https://code.visualstudio.com) (VS Code). VS Code allows you to edit Jupyter notebooks outside of the traditional Jupyter ecosystem.

Fortunately, moving code development to your personal laptop or desktop does not mean giving up direct access to Greene’s computing resources. By linking a local IDE to the Greene cluster, you can take advantage of advanced tools and extensions — including AI features — while still running your code on powerful remote hardware.

This guide walks through the process of configuring VS Code to connect to Greene, affording you full control over your development environment without sacrificing computational power.

Note that the guide assumes familiarity with Singularity containers and conda environments — NYU HPC's recommended approach to creating independent and reproducible computing environments. If you’re new to this approach, start [here](https://sites.google.com/nyu.edu/nyu-hpc/hpc-systems/greene/software/singularity-with-miniconda) to learn how to create a writable container overlay, install Miniforge, and configure a conda environment inside the container. If you’re interested in using your Singularity setup with the OnDemand web interface, [this guide](https://sites.google.com/nyu.edu/nyu-hpc/hpc-systems/greene/software/open-ondemand-ood-with-condasingularity) covers that process.

## Steps to Link VS Code to a Greene Compute Node

1. **Connect to NYU-NET**

    You’ll need to be on NYU’s network ([NYU-NET](https://www.nyu.edu/life/information-technology/infrastructure/network-services/nyu-net.html)). If you‘e on a campus wired or WiFi connection, you’re on NYU-NET already. If you‘re off campus, you must connect through NYU's VPN using the [Cisco AnyConnect software client](https://www.nyu.edu/life/information-technology/infrastructure/network-services/vpn.html).

2. **Configure SSH**

    Set up a Secure Shell (SSH) configuration on your local machine by adding the entries below to your `~/.ssh/config` file. Don't forget to replace `<NetID>` with your actual NetID.

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
    ```

    The `greene-login` entry uses SSH keys to simplify connection to the Greene login node and avoid repeated password prompts.

    Because computation-heavy code should never be run on a login node, we’re going to request resources on a compute node. The SSH configuration file‘s `greene-compute` entry makes it easy to connect to that node once it‘s assigned. You’ll update the placeholder `ComputeNode` later to reflect the node you've been allocated.

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
    
    After resources are allocated (which can take time), you’ll be dropped into a shell on one of Greene's compute nodes. To confirm the name of your assigned node, you can run `hostname` at your Terminal prompt. You'll see something like `cm026.hpc.nyu.edu`.

5. **Edit Your SSH Configuration to Reference Your Assigned Compute Node**

    Next, edit your `~/.ssh/config` file to specify the compute node you've been assigned. For example, if you are allocated `cm26.hpc.nyu.edu`, swap the placeholder with `cm026.hpc.nyu.edu`.
    
    **Note:** You can either edit your SSH configuration file through your local operating system (e.g., macOS or Windows) or through the Terminal. If you wish to edit `~/.ssh/config` in the Terminal using `vim` or `nano` (or another editor), be sure to open a _new Terminal window_. This file lives on your local machine and you won't be able to find it through the compute node window opened in the last step!

6. **Launch a Jupyter Lab Server Within a Containerized Conda Environment**

    This step launches your Conda environment inside a Singularity container and starts an Jupyter Lab server inside it. The command below mounts your writable overlay, activates the specified Conda environment inside the container, and starts a Jupyter Lab server.

    Update the configuration variables to reflect your own file paths and environment name, then paste and run in the compute node you were dropped into in the last step.

    ```
    # === Configuration ===
    OVERLAY_PATH="/scratch/${USER}/word2gm_ol/overlay-15GB-500K.ext3"
    CONTAINER_PATH="/scratch/work/public/singularity/cuda12.6.3-cudnn9.5.1-ubuntu22.04.5.sif"
    CONDA_ENV_NAME="word2gm-fast2"

    # === Jupyter cleanup ===
    echo "🧹 Cleaning up stale Jupyter runtime files..."
    rm -f ~/.local/share/jupyter/runtime/nbserver-*.json
    rm -f ~/.local/share/jupyter/runtime/kernel-*.json

    # If needed, kill lingering jupyter servers
    if pgrep -u "$USER" -f "jupyter-lab" > /dev/null; then
        echo "✂️  Killing old JupyterLab processes..."
        pkill -u "$USER" -f "jupyter-lab"
    fi

    # === Run Singularity command ===
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

    The Jupyter server acts as a bridge between VS Code and the remote Python kernel running inside the Singularity container.

7. **Get Port Number and URL from Jupyter Server Output**

    One part the output of the Jupyter server command is crucial. It will look something like this:

    ```
    To access the server, open this file in a browser:
        file:///home/edk202/.local/share/jupyter/runtime/jpserver-2205529-open.html
    Or copy and paste one of these URLs:
        http://cm005.hpc.nyu.edu:8889/lab?token=33d4b561e076e9bdc765dd2acc16b7fc00e431954b6bc5ad
        http://127.0.0.1:8889/lab?token=33d4b561e076e9bdc765dd2acc16b7fc00e431954b6bc5ad
    ```

    The last line is what we need. The URL as a whole is what we'll use to access the Jupyter kernel in VS Code. But before that, we need to ensure that your local machine is listening to the compute node on the right port. That port is listed after the colon in the first part of the URL — in this example, it's `8889`.

8. **Forward the Local Port to the Remote Port**

    You must now forward local port `8888` to the remote port you find in the Jupyter URL. This provides a secure way for your local machine to "listen" to the Jupyter server you just launched inside the remote Singularity container.

    If the remote port is `8889`, you would use this command to get your local machine to listen to the compute:

    ```
    ssh -N -L 8888:localhost:8889 greene-compute
    ```

    After to you run this command, no output will be printed and the window will appear to hang. This is normal; your local machine is listening.

    **Note:** This command needs to be executed on your local machine, so be sure to run it in a new Terminal window; it won't work in the compute node window.