# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains **Hail on AWS Spot Instances**, a CloudFormation tool from Harvard Medical School (HMS-DBMI) for deploying [Hail 0.2](https://www.hail.is) genomics analysis framework on Amazon EMR clusters using cost-effective spot instances.

## Commands

### Deploy Hail EMR Cluster

```bash
cd src
# Edit configuration first
vim config_EMR_spot.yaml
# Deploy cluster (takes 10-15 minutes)
sh cloudformation_hail_spot.sh
```

## Architecture

**Technology Stack**: Python 3.11, Bash, AWS EMR 7.12.0, Spark 3.5.x, Java 11, Jupyter Lab, Amazon Linux 2023

**Deployment Flow**:
1. `cloudformation_hail_spot.sh` - Entry point, calls run.sh
2. `run.sh` - Validates AWS credentials, invokes Python deployer
3. `EMR_deploy_and_install_spot.py` - Uses boto3/AWS CLI to create EMR cluster
4. Bootstrap scripts run on EMR nodes:
   - `install_hail.sh` - Master orchestrator (install_hail_and_python36.sh for legacy)
   - `bootstrap_python.sh` - Python 3.11 environment setup (bootstrap_python36.sh for legacy)
   - `hail_build.sh` - Compiles Hail wheel with Spark 3.5.x
   - `jupyter_run.sh` - Launches Jupyter Lab on port 8192

**Key Files**:
- `src/config_EMR_spot.yaml` - Primary configuration (EMR release, cluster name, instance types, bid prices, S3 bucket, security groups, Hail version)
- `src/run_when_new_instance_added.sh` - Cron job for auto-recovery when spot instances are replaced
- `notebook/` - Sample Jupyter notebooks including GWAS tutorial

## Configuration

### EMR Cluster Configuration (`src/config_EMR_spot.yaml`)

Key parameters:
- `EMR_RELEASE_LABEL` - EMR version (default: emr-7.12.0)
- `EMR_CLUSTER_NAME`, `REGION`, `SUBNET_ID` - Cluster identification
- `MASTER_INSTANCE_TYPE`, `WORKER_INSTANCE_TYPE` - EC2 instance types (m6i/r6i generation recommended)
- `WORKER_COUNT`, `WORKER_BID_PRICE` - Spot instance configuration
- `S3_BUCKET` - Log storage location (use s3:// prefix)
- `KEY_NAME`, `PATH_TO_KEY` - EC2 key pair (name without .pem extension)
- `WORKER_SECURITY_GROUP`, `MASTER_SECURITY_GROUP` - Security groups (port 8192 required for Jupyter)
- `HAIL_VERSION` - Git hash or "current" for latest

### Version Requirements

- **EMR**: 7.12.0 or later (provides Spark 3.5.x)
- **Hail**: 0.2.137+ (requires Spark 3.5.x, Python 3.10+, Java 11)
- **Python**: 3.10 or later
- **Java**: 11 (Amazon Corretto)

### Prerequisites

- Python 3.10+ with boto3, pandas, paramiko, pyyaml, botocore
- AWS CLI v2 configured (`aws configure`)
- EC2 key pair with proper permissions (`chmod 400 my-key.pem`)
- EMR service roles (`aws emr create-default-roles`)

## Access

- **Jupyter Lab**: `<master-ip>:8192` with password `avillach`
- **Master node SSH**: `ssh -i key.pem hadoop@<master-dns>`
- **EMR logs**: `/tmp/cloudcreation_log.out` on master node
