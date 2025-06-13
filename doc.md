# Remote Development on NYU HPC’s Greene Cluster

New York University’s High-Performance Computing (HPC) facility offers browser-based access to Jupyter Notebook, Jupyter Lab, and other applications through the [OnDemand service](https://sites.google.com/nyu.edu/nyu-hpc/accessing-hpc#h.7kawz2pfzl9d). With OnDemand, you don't run Jupyter on your personal computer; you write and execute code on a server-side Jupyter instance through your web browser.

This approach to code development offers many advantages, including seamless access to Greene‘s full range of [computing resources](https://www.nyu.edu/research/navigating-research-technology/nyu-greene.html). Nevertheless, browser-based coding has downsides. OnDemand limits users‘ choice of computing environments and restricts the installation of smart coding tools like AI-assisted code completion and AI copilots.

For users who want more flexibility, there are benefits to coding in a fully featured and extensible _local_ Integrated Development Environment (IDE) such as [Visual Studio Code](https://code.visualstudio.com) (VS Code).

Fortunately, moving code development to your personal laptop or desktop does not mean giving up direct access to Greene’s computing resources. By linking a local IDE to the Greene cluster, you can take advantage of advanced tools and extensions — including AI features — while still running your code on powerful remote hardware.

This guide walks through the process of configuring VS Code to connect to Greene, allowing you full control over your development environment without sacrificing computational power.

Note that the guide assumes familiarity with Singularity containers and conda environments — NYU HPC's recommended approach to creating fully independent and reproducible computing environments. If you’re new to this approach, start [here](https://sites.google.com/nyu.edu/nyu-hpc/hpc-systems/greene/software/singularity-with-miniconda) to learn how to create a writable container overlay, install Miniforge, and configure a conda environment inside the container. If you’re interested in using your Singularity setup with the OnDemand web interface, [this guide](https://sites.google.com/nyu.edu/nyu-hpc/hpc-systems/greene/software/open-ondemand-ood-with-condasingularity) covers that process.

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
    HostName cm001.hpc.nyu.edu     # Replace with your assigned compute node
    User <NetID>
    ProxyJump greene-login
    ```

    The `greene-login` entry uses SSH keys to simplify connection to the Greene login node and avoid repeated password prompts.

    Because computation-heavy code should never be run on a login node, we’re going to request resources on a compute node. The `greene-compute` entry makes it easy to connect to that node once it‘s assigned. You’ll update the placeholder `cm001` later based on which specific node you’re allocated.

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

    You’ll be dropped into a shell on an assigned compute node. To confirm the name of your current node, you can run `hostname` at your Terminal prompt. You'll see something like `cm026.hpc.nyu.edu`.

5. **Launch a Jupyter Lab Server Within a Containerized Conda Environment**

    This step launches your Conda environment inside a Singularity container and starts a Jupyter Lab kernel server inside it. The command below mounts your writable overlay, activates the specified Conda environment inside the container, and starts a Jupyter Lab session.

    Update the configuration variables to reflect your own file paths and environment name, the past and run in the compute node you were dropping into in the last step.

    ```
    # === Configuration ===
    OVERLAY_PATH="/scratch/${USER}/word2gm_ol/overlay-15GB-500K.ext3"
    CONTAINER_PATH="/scratch/work/public/singularity/cuda12.6.3-cudnn9.5.1-ubuntu22.04.5.sif"
    CONDA_ENV_NAME="word2gm-fast2"

    # === Run Singularity command ===
    singularity exec \
    --overlay "${OVERLAY_PATH}:rw" \
    "${CONTAINER_PATH}" \
    bash -c "
        source /ext3/env.sh
        conda activate '${CONDA_ENV_NAME}'
        jupyter lab --no-browser --port=8888 --ip=0.0.0.0
    "
    ```

    Even though we're planning to work in VS Code, launching a Jupyter Lab server inside the container is necessary because VS Code connects to Jupyter kernels through the Jupyter protocol. The Jupyter server acts as a bridge between your local editor and the remote Python kernel running inside the Singularity container.