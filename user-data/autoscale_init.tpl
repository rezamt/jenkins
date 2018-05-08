#!/usr/bin/env bash

echo 'ECS_CLUSTER=${jenkins_cluster}' >> /etc/ecs/ecs.config

# Mount EFS volume
yum install -y nfs-utils

EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`

EC2_REGION=${aws_region}

EFS_FILE_SYSTEM_ID=${jenkins_efs}

EFS_PATH=$EC2_AVAIL_ZONE.$EFS_FILE_SYSTEM_ID.efs.$EC2_REGION.amazonaws.com

mkdir /data
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 $EFS_PATH:/ /data

# Give ownership to jenkins user
chown 1000 /data