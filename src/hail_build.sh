#!/bin/bash

# Hail Installation Script for EMR 7.x (Amazon Linux 2023)
# Installs Hail 0.2.137+ from PyPI with Spark 3.5.x and Java 11

# Error message
error_msg ()
{
  echo 1>&2 "Error: $1"
  exit 1
}

# Usage
usage()
{
echo "Usage: hail_build.sh [-v | --version <version>] [-h | --help]

Options:
-v | --version <version>
    Specify a Hail version to install (e.g., 0.2.137).
    If not specified or 'current', installs the latest version from PyPI.

-h | --help
    Displays this menu"
    exit 1
}

HAIL_VERSION=""

# Read input parameters
while [ "$1" != "" ]; do
    case $1 in
        -v|--version)   shift
                        HAIL_VERSION="$1"
                        ;;
        -h|--help)      usage
                        ;;
        -*)
                        error_msg "unrecognized option: $1"
                        ;;
        *)              usage
    esac
    shift
done

IS_MASTER=false

if grep isMaster /mnt/var/lib/info/instance.json | grep true;
then
  IS_MASTER=true
fi

echo "Installing Hail ${HAIL_VERSION:-latest}"

if [ "$IS_MASTER" = true ]; then
    echo "Configuring master node for Hail..."

    # Set JAVA_HOME for Java 11 (required for Hail 0.2.137+)
    export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64
    export PATH=$JAVA_HOME/bin:$PATH

    # Add to profile for persistence
    echo "export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64" | sudo tee /etc/profile.d/java11.sh
    echo "export PATH=\$JAVA_HOME/bin:\$PATH" | sudo tee -a /etc/profile.d/java11.sh

    echo "Java version:"
    java -version 2>&1

    # Install Hail from PyPI
    echo "Installing Hail from PyPI..."
    if [ -n "$HAIL_VERSION" ] && [ "$HAIL_VERSION" != "current" ]; then
        echo "Installing Hail version: $HAIL_VERSION"
        sudo /usr/bin/python3.11 -m pip install "hail==$HAIL_VERSION"
    else
        echo "Installing latest Hail version"
        sudo /usr/bin/python3.11 -m pip install hail
    fi

    # Verify installation
    echo "Verifying Hail installation..."
    /usr/bin/python3.11 -c "import hail; print('Hail version:', hail.__version__)" || {
        error_msg "Hail installation verification failed"
    }

    echo "Hail installation completed successfully"
else
    echo "Worker node - Hail installation not required on workers"
fi
