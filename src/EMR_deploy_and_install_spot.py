#!/usr/bin/env python3
"""
EMR Deployment Script for Hail on AWS Spot Instances
Deploys EMR 7.x cluster with Spark 3.5.x and Hail support

Requirements:
- Python 3.10+
- boto3, paramiko, pyyaml, botocore
- AWS CLI configured with appropriate permissions
"""

import boto3
import time
import sys
import botocore
import paramiko
import re
import os
import yaml
import json

PATH = os.path.dirname(os.path.abspath(__file__))

# Load configuration - use safe_load to avoid deprecation warning
# Support command-line argument for config file
import os.path
import argparse

parser = argparse.ArgumentParser(description='Deploy Hail EMR Cluster')
parser.add_argument('--config', '-c', type=str, help='Path to configuration YAML file')
parser.add_argument('--profile', '-p', type=str, help='AWS profile name to use')
args, unknown = parser.parse_known_args()

# Set AWS profile if specified
if args.profile:
    os.environ['AWS_PROFILE'] = args.profile
    print(f"Using AWS profile: {args.profile}")

# Determine config file to use
if args.config:
    config_file = args.config
elif os.path.exists(PATH + "/config_EMR_spot_test.yaml"):
    config_file = PATH + "/config_EMR_spot_test.yaml"
else:
    config_file = PATH + "/config_EMR_spot.yaml"

print(f"Using config file: {config_file}")
with open(config_file) as f:
    c = yaml.safe_load(f)

config = c['config']

# Get EMR release label from config, default to emr-7.5.0
EMR_RELEASE_LABEL = config.get('EMR_RELEASE_LABEL', 'emr-7.5.0')

# Build the EMR create-cluster command for EMR 7.x
# EMR 7.x uses Amazon Linux 2023 and includes Spark 3.5.x

# EC2 attributes
ec2_attributes = {
    "KeyName": config['KEY_NAME'],
    "InstanceProfile": "EMR_EC2_DefaultRole",
    "SubnetId": config['SUBNET_ID'],
    "EmrManagedSlaveSecurityGroup": config['WORKER_SECURITY_GROUP'],
    "EmrManagedMasterSecurityGroup": config['MASTER_SECURITY_GROUP']
}

# Check if using Spot instances
use_spot = config.get('USE_SPOT', 'true').lower() == 'true'
bid_price = config.get('WORKER_BID_PRICE', '')

# Instance groups configuration
master_instance_group = {
    "InstanceCount": 1,
    "EbsConfiguration": {
        "EbsBlockDeviceConfigs": [
            {
                "VolumeSpecification": {
                    "SizeInGB": int(config['MASTER_HD_SIZE']),
                    "VolumeType": "gp3"
                },
                "VolumesPerInstance": 1
            }
        ]
    },
    "InstanceGroupType": "MASTER",
    "InstanceType": config['MASTER_INSTANCE_TYPE'],
    "Name": "Master-Instance"
}

worker_instance_group = {
    "InstanceCount": int(config['WORKER_COUNT']),
    "EbsConfiguration": {
        "EbsBlockDeviceConfigs": [
            {
                "VolumeSpecification": {
                    "SizeInGB": int(config['WORKER_HD_SIZE']),
                    "VolumeType": "gp3"
                },
                "VolumesPerInstance": 1
            }
        ]
    },
    "InstanceGroupType": "CORE",
    "InstanceType": config['WORKER_INSTANCE_TYPE'],
    "Name": "Core-Group"
}

# Add BidPrice only if using Spot instances
if use_spot and bid_price:
    worker_instance_group["BidPrice"] = bid_price
    print(f"Using SPOT instances with bid price: ${bid_price}/hour")
else:
    print("Using ON-DEMAND instances")

instance_groups = [master_instance_group, worker_instance_group]

# EMR configurations for Spark 3.5.x optimization
configurations = [
    {
        "Classification": "spark",
        "Properties": {
            "maximizeResourceAllocation": "true"
        }
    },
    {
        "Classification": "spark-defaults",
        "Properties": {
            "spark.driver.memory": "4g",
            "spark.executor.memory": "4g",
            "spark.dynamicAllocation.enabled": "true"
        }
    },
    {
        "Classification": "yarn-site",
        "Properties": {
            "yarn.nodemanager.vmem-check-enabled": "false"
        }
    }
]

# Tags
tags = f"project={config['PROJECT_TAG']} Owner={config['OWNER_TAG']} Name={config['EC2_NAME_TAG']}"

# Build AWS CLI command
# Note: For EMR 7.x, bootstrap scripts need to be updated for Amazon Linux 2023
command = (
    f"aws emr create-cluster "
    f"--applications Name=Hadoop Name=Spark Name=JupyterEnterpriseGateway "
    f"--tags 'project={config['PROJECT_TAG']}' 'Owner={config['OWNER_TAG']}' 'Name={config['EC2_NAME_TAG']}' "
    f"--ec2-attributes '{json.dumps(ec2_attributes)}' "
    f"--service-role EMR_DefaultRole "
    f"--release-label {EMR_RELEASE_LABEL} "
    f"--log-uri '{config['S3_BUCKET']}' "
    f"--name '{config['EMR_CLUSTER_NAME']}' "
    f"--instance-groups '{json.dumps(instance_groups)}' "
    f"--configurations '{json.dumps(configurations)}' "
    f"--auto-scaling-role EMR_AutoScaling_DefaultRole "
    f"--ebs-root-volume-size 50 "
    f"--scale-down-behavior TERMINATE_AT_TASK_COMPLETION "
    f"--region {config['REGION']} "
    f"--bootstrap-actions Path=\"s3://{config['S3_BUCKET'].replace('s3://', '').rstrip('/')}/hail_bootstrap/bootstrap_python.sh\""
)

print("\n" + "=" * 60)
print("Deploying Hail EMR Cluster")
print("=" * 60)
print(f"\nEMR Release: {EMR_RELEASE_LABEL}")
print(f"Master Instance: {config['MASTER_INSTANCE_TYPE']}")
print(f"Worker Instance: {config['WORKER_INSTANCE_TYPE']} x {config['WORKER_COUNT']}")
print(f"Region: {config['REGION']}")
print("\n" + "-" * 60)
print("AWS CLI Command:")
print("-" * 60)
print(command)
print("\n")

# Execute the command
cluster_id_json = os.popen(command).read()

try:
    # Parse JSON output from AWS CLI
    response = json.loads(cluster_id_json)
    cluster_id = response.get('ClusterId')
    if not cluster_id:
        raise ValueError("ClusterId not found in response")
except (json.JSONDecodeError, ValueError) as e:
    print("Error: Failed to create EMR cluster")
    print(f"Response: {cluster_id_json}")
    print(f"Parse error: {e}")
    sys.exit(1)

print(f"Cluster ID: {cluster_id}")

# Gives EMR cluster information
client_EMR = boto3.client('emr', region_name=config['REGION'])

# Cluster state update
status_EMR = 'STARTING'
tic = time.time()

# Wait until the cluster is created
while status_EMR != 'EMPTY':
    print('Creating EMR cluster...')
    details_EMR = client_EMR.describe_cluster(ClusterId=cluster_id)
    status_EMR = details_EMR.get('Cluster').get('Status').get('State')
    print(f'Cluster status: {status_EMR}')
    time.sleep(10)

    if status_EMR == 'WAITING':
        print('\nCluster successfully created! Starting Hail installation...')
        toc = time.time() - tic
        print(f"\nTotal time to provision cluster: {toc/60:.2f} minutes")
        break

    if status_EMR == 'TERMINATED_WITH_ERRORS':
        error_msg = details_EMR.get('Cluster').get('Status').get('StateChangeReason', {}).get('Message', 'Unknown error')
        print(f"\nError: {error_msg}")
        sys.exit("Cluster creation failed. Ending installation...")

# Get public DNS from master node
master_dns = details_EMR.get('Cluster').get('MasterPublicDnsName')
master_IP = re.sub("-", ".", master_dns.split(".")[0].split("ec2-")[1])

print('\n' + '=' * 60)
print('Cluster Information')
print('=' * 60)
print(f'Master DNS: {master_dns}')
print(f'Master IP: {master_IP}')
print(f'Cluster ID: {cluster_id}')
print('=' * 60 + '\n')

# Copy the key into the master
key_path = config['PATH_TO_KEY'] + config['KEY_NAME'] + '.pem'
command = f"scp -o 'StrictHostKeyChecking no' -i {key_path} {key_path} hadoop@{master_dns}:/home/hadoop/.ssh/id_rsa"
os.system(command)
print('Copying keys to master node...')

# Copy the installation script into the master
install_script = PATH + '/install_hail.sh'
# Fall back to old filename if new one doesn't exist
if not os.path.exists(install_script):
    install_script = PATH + '/install_hail_and_python36.sh'

command = f"scp -o 'StrictHostKeyChecking no' -i {key_path} {install_script} hadoop@{master_dns}:/home/hadoop/install_hail.sh"
os.system(command)

print('\nInstalling Hail and dependencies...')
print('Allow 10-15 minutes for full installation (Hail compilation takes time)')
print(f'\nJupyter Lab will be available at: http://{master_IP}:8192')
print('Default password: avillach\n')

# Connect via SSH and run installation
key = paramiko.RSAKey.from_private_key_file(key_path)
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(hostname=master_IP, username="hadoop", pkey=key)

# Execute installation command
VERSION = config['HAIL_VERSION']
command = f'chmod +x /home/hadoop/install_hail.sh && /home/hadoop/install_hail.sh -v {VERSION}'
stdin, stdout, stderr = client.exec_command(command)

# Close the client connection
client.close()

print('=' * 60)
print('Deployment initiated successfully!')
print('=' * 60)
print(f'\nMonitor installation progress:')
print(f'  ssh -i {key_path} hadoop@{master_dns}')
print(f'  tail -f /tmp/cloudcreation_log.out')
print(f'\nJupyter Lab: http://{master_IP}:8192')
print(f'Password: avillach')
print('=' * 60)
