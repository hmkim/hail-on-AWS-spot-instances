#!/bin/bash

# Script to handle new spot instances added to the cluster
# Runs via cron every minute to detect and configure new instances

# Grabs the list of EC2s
sudo grep -i privateip /mnt/var/lib/info/*.txt | sort -u | cut -d "\"" -f 2 > /tmp/t2.txt

# Queries for the EC2 IDs
CLUSTERID="$(jq -r .jobFlowId /mnt/var/lib/info/job-flow.json)"
REGION="$(jq -r .region /mnt/var/lib/info/extraInstanceData.json)"
aws emr list-instances --cluster-id ${CLUSTERID} --region ${REGION} | jq -r .Instances[].Ec2InstanceId > /tmp/ec2list2.txt
KEY=$(ls ~/.ssh/id_rsa/)

# Check if there was an EC2 addition
if [ -z "$(diff /tmp/ec2list2.txt /tmp/ec2list1.txt 2>/dev/null)" ]; then
  echo "$(date): No new instances detected/added"
else
  for WORKERIP in $(diff /tmp/t1.txt /tmp/t2.txt | grep "> " | sed 's/> //')
  do
     # Distribute keys to workers for account hadoop
     echo "$(date): New instance detected at $WORKERIP - Updating cluster"

     # Distribute SSH keys
     scp -o "StrictHostKeyChecking no" -i ~/.ssh/id_rsa/${KEY} ~/.ssh/authorized_keys ${WORKERIP}:/home/hadoop/.ssh/authorized_keys

     # Distribute Hail wheel if it exists
     if ls $HOME/hail-*.whl 1> /dev/null 2>&1; then
         scp -i $HOME/.ssh/id_rsa/${KEY} $HOME/hail-*.whl $WORKERIP:/home/hadoop/
     fi

     # Update IP lists
     sudo grep -i privateip /mnt/var/lib/info/*.txt | sort -u | cut -d "\"" -f 2 > /tmp/t1.txt
     aws emr list-instances --cluster-id ${CLUSTERID} --region ${REGION} | jq -r .Instances[].Ec2InstanceId > /tmp/ec2list1.txt

     # Restart YARN resource manager (EMR 7.x uses systemctl)
     sudo systemctl restart hadoop-yarn-resourcemanager 2>/dev/null || \
         (sudo stop hadoop-yarn-resourcemanager; sleep 1; sudo start hadoop-yarn-resourcemanager)

     echo "$(date): Instance $WORKERIP configured successfully"
  done
fi
