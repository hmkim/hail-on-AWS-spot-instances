#!/bin/bash

# Script to update Hail on an existing EMR cluster
# For EMR 7.x with Spark 3.5.x

# Error message
error_msg ()
{
  echo 1>&2 "Error: $1"
  exit 1
}

# Usage
usage()
{
echo "Usage: update_hail.sh [-v | --version <git hash>] [-h | --help]

Options:
-v | --version <git hash>
    This option takes either the abbreviated (8-12 characters) or the full size hash (40 characters).
    When provided, the command builds Hail from the specified git commit.
    If no version is given or 'current', Hail will be compiled from the latest main branch.

-h | --help
	Displays this menu"
    exit 1
}

# Read input parameters
while [ "$1" != "" ]; do
    case $1 in
        -v|--version)	shift
                        HASH="$1"
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

echo "Running Hail update with version: ${HASH:-current}"

# Remove existing Hail installation
sudo rm -rf hail 2>/dev/null

# Build Hail
./hail_build.sh -v ${HASH:-current}

# Restart YARN resource manager (EMR 7.x uses systemctl)
sudo systemctl restart hadoop-yarn-resourcemanager 2>/dev/null || \
    (sudo stop hadoop-yarn-resourcemanager; sleep 1; sudo start hadoop-yarn-resourcemanager)

echo "Hail update completed. Restart Jupyter kernel to use the new version."
