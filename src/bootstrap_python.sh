#!/bin/bash
set -e

# Bootstrap script for EMR 7.x (Amazon Linux 2023)
# Installs Python 3.10+ and required packages for Hail

export PATH=$PATH:/usr/local/bin

cd $HOME
mkdir -p $HOME/.ssh/id_rsa

echo "Installing Python and dependencies for Amazon Linux 2023..."

# Function to run dnf with retry (handles RPM lock conflicts)
dnf_install() {
    local max_attempts=10
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt: Installing $@"
        if sudo dnf install -y "$@"; then
            return 0
        fi
        echo "dnf install failed (attempt $attempt/$max_attempts), waiting 30 seconds..."
        sleep 30
        attempt=$((attempt + 1))
    done
    echo "ERROR: dnf install failed after $max_attempts attempts"
    return 1
}

# AL2023 uses dnf instead of yum, but yum is aliased to dnf
# Python 3.9 is default on AL2023, we need Python 3.10+ for Hail 0.2.137

# Wait for any EMR provisioning to complete
echo "Waiting for EMR provisioning to complete..."
sleep 60

# Install Python 3.11 and all system dependencies FIRST before upgrading pip
# (pip upgrade can break dnf if done before dnf install commands)
dnf_install python3.11 python3.11-devel python3.11-pip

if grep isMaster /mnt/var/lib/info/instance.json | grep true; then
    echo "Configuring master node..."

    # Install build dependencies (must be done before pip upgrade)
    dnf_install gcc gcc-c++ cmake git
    dnf_install lz4 lz4-devel
    dnf_install openblas openblas-devel lapack lapack-devel

    # Master node packages list
    PACKAGES="wheel
    pandas
    numpy
    scipy
    bokeh
    requests
    boto3
    python-magic
    ipywidgets
    parsimonious
    aiohttp
    aiohttp_session
    asyncinit
    avro
    decorator
    deprecated
    dill
    frozenlist
    humanize
    nest_asyncio
    orjson
    plotly
    rich
    tabulate
    uvloop
    jupyterlab"
else
    echo "Configuring worker node..."

    # Install minimal build dependencies for workers
    dnf_install lz4 lz4-devel

    # Worker node packages (without JupyterLab)
    PACKAGES="wheel
    pandas
    numpy
    scipy
    bokeh
    requests
    boto3
    python-magic
    parsimonious
    aiohttp
    decorator
    deprecated
    dill
    humanize
    orjson"
fi

# IMPORTANT: Do NOT modify system python3 - it breaks EMR application provisioning
# EMR uses system python3.9 for internal operations
# We will use python3.11 explicitly for Hail

# IMPORTANT: Do NOT upgrade pip globally - it breaks dnf by modifying system Python paths
# AL2023's pip 22.3.1 is recent enough for our needs

echo "Installing Python packages using python3.11 directly..."
for PACKAGE_NAME in $PACKAGES
do
    echo "Installing $PACKAGE_NAME..."
    sudo /usr/bin/python3.11 -m pip install "$PACKAGE_NAME" || echo "Warning: Failed to install $PACKAGE_NAME"
done

# Create a symlink for convenience (not affecting system python3)
sudo ln -sf /usr/bin/python3.11 /usr/local/bin/python3.11

echo "Bootstrap completed successfully"
echo "Note: Use python3.11 or /usr/bin/python3.11 for Hail operations"
