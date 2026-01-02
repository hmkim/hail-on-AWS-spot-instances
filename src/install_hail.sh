#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/tmp/cloudcreation_log.out 2>&1

# Install script for Hail on EMR 7.x (Amazon Linux 2023)

export HAIL_HOME="/opt/hail-on-AWS-spot-instances"
export HASH="current"

# Error message
error_msg ()
{
  echo 1>&2 "Error: $1"
  exit 1
}

# Usage
usage()
{
echo "Usage: install_hail.sh [-v | --version <git hash>] [-h | --help]

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

echo "=========================================="
echo "Hail Installation Script for EMR 7.x"
echo "=========================================="
echo "Starting installation at $(date)"
echo "Hail version: ${HASH}"

chmod 700 $HOME/.ssh/id_rsa/
KEY=$(ls ~/.ssh/id_rsa/)

# Distribute keys to worker nodes
echo "Distributing SSH keys to worker nodes..."
for WORKERIP in $(sudo grep -i privateip /mnt/var/lib/info/*.txt | sort -u | cut -d "\"" -f 2)
do
   scp -o "StrictHostKeyChecking no" -i ~/.ssh/id_rsa/${KEY} ~/.ssh/authorized_keys ${WORKERIP}:/home/hadoop/.ssh/authorized_keys
done

echo 'Keys successfully copied to the worker nodes'

# Clone the hail-on-AWS-spot-instances repository
sudo mkdir -p /opt
sudo chmod 777 /opt/
sudo chown hadoop:hadoop /opt
cd /opt
git clone https://github.com/hms-dbmi/hail-on-AWS-spot-instances.git
cd $HAIL_HOME/src

# Build and install Hail
echo "Building Hail..."
./hail_build.sh -v $HASH

# Set the time zone
sudo timedatectl set-timezone America/New_York || \
    sudo cp /usr/share/zoneinfo/America/New_York /etc/localtime

# Get IPs and names of EC2 instances (workers) to monitor if a worker dropped
sudo grep -i privateip /mnt/var/lib/info/*.txt | sort -u | cut -d "\"" -f 2 > /tmp/t1.txt
CLUSTERID="$(jq -r .jobFlowId /mnt/var/lib/info/job-flow.json)"
aws emr list-instances --cluster-id ${CLUSTERID} | jq -r .Instances[].Ec2InstanceId > /tmp/ec2list1.txt

# Setup crontab to check dropped instances every minute and install SW as needed in new instances
sudo echo "* * * * * /opt/hail-on-AWS-spot-instances/src/run_when_new_instance_added.sh >> /tmp/cloudcreation_log.out 2>&1 # min hr dom month dow" | crontab -

echo "Starting Jupyter Lab..."
./jupyter_run.sh

echo "=========================================="
echo "Installation completed at $(date)"
echo "=========================================="
