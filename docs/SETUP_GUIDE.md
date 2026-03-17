# Hail on AWS EMR 7.12.0 Comprehensive Setup Guide

This document covers the complete process and key considerations for setting up Hail 0.2.137 on AWS EMR 7.12.0.

## Version Information

| Component | Version | Notes |
|-----------|---------|-------|
| EMR | 7.12.0 | Based on Amazon Linux 2023 |
| Spark | 3.5.x | Included in EMR 7.12.0 |
| Hail | 0.2.137+ | Installed from PyPI |
| Python | 3.11 | Dedicated for Hail (separate from system Python 3.9) |
| Java | 11 (Amazon Corretto) | Hail requirement |
| OS | Amazon Linux 2023 | yum → dnf |

## Key Requirements

### 1. Java 11 Required

Hail 0.2.137 requires Java 11. EMR 7.x uses Java 17 by default, so you must change to Java 11.

**Symptoms (when using Java 17):**
```
java.lang.UnsupportedClassVersionError: is/hail/backend/service/Main has been compiled by a more recent version of the Java Runtime
```

**Solution (applied in hail_build.sh):**
```bash
# Change Spark's Java configuration from Java 17 to Java 11
sudo sed -i 's|JAVA17_HOME=/usr/lib/jvm/jre-17|JAVA11_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64|g' /etc/spark/conf/spark-env.sh
sudo sed -i 's|export JAVA_HOME=\$JAVA17_HOME|export JAVA_HOME=\$JAVA11_HOME|g' /etc/spark/conf/spark-env.sh
```

### 2. xlarge or Larger Instance Types Required

EMR 7.12.0 only supports xlarge or larger instance types.

| Role | Recommended Type | Notes |
|------|-----------------|-------|
| Master | m6i.xlarge | Minimum xlarge required |
| Worker | r6i.2xlarge, r6i.4xlarge | Memory-optimized recommended |

**Unsupported types:** large, medium, small

### 3. Use Python 3.11

Hail is installed on Python 3.11. Do not modify system Python (3.9).

**Correct usage:**
```bash
python3.11 -c "import hail as hl; print(hl.__version__)"
```

**Incorrect usage:**
```bash
python3 -c "import hail as hl; print(hl.__version__)"  # Error
```

### 4. Hail JAR Path

Location of JAR file for Hail installed from PyPI:
```
/usr/local/lib/python3.11/site-packages/hail/backend/hail-all-spark.jar
```

This path is prioritized in jupyter_run.sh.

## Deployment Architecture

```
cloudformation_hail_spot.sh
    └── run.sh (AWS credential validation)
        └── EMR_deploy_and_install_spot.py (Create EMR cluster with boto3)
            └── Bootstrap Actions (downloaded from S3):
                ├── bootstrap_python.sh (Python 3.11 environment setup)
                ├── install_hail.sh (Master node setup orchestration)
                │   ├── hail_build.sh (Hail PyPI installation, Java 11 setup)
                │   └── jupyter_run.sh (Start Jupyter Lab)
                └── run_when_new_instance_added.sh (Cron for spot instance recovery)
```

## Deployment Steps

### Step 1: Prerequisites

```bash
# Configure AWS CLI
aws configure

# Create EMR default roles
aws emr create-default-roles

# Set EC2 key pair permissions
chmod 400 my-key.pem
```

### Step 2: Edit Configuration File

`src/config_EMR_spot.yaml`:
```yaml
config:
  EMR_CLUSTER_NAME: "my-hail-02-cluster"
  EMR_RELEASE_LABEL: "emr-7.12.0"
  EC2_NAME_TAG: "my-hail-EMR"
  OWNER_TAG: "emr-owner"
  PROJECT_TAG: "my-project"
  MICROSERVICE_TAG: "caris-poc"
  REGION: "ap-southeast-1"
  MASTER_INSTANCE_TYPE: "m6i.xlarge"      # xlarge or larger required
  WORKER_INSTANCE_TYPE: "r6i.4xlarge"
  WORKER_COUNT: "4"
  WORKER_BID_PRICE: "0.50"
  S3_BUCKET: "s3://your-bucket/"
  KEY_NAME: "my-key"
  PATH_TO_KEY: "/path/to/key/"
  HAIL_VERSION: "current"
```

### Step 3: Deploy Cluster

```bash
cd src
sh cloudformation_hail_spot.sh
```

Deployment time: approximately 10-15 minutes

### Step 4: Configure Security Groups

Add the following inbound rules to the EMR master security group:

| Port | Purpose |
|------|---------|
| 22 | SSH access |
| 8192 | Jupyter Lab |

```bash
# Get your IP
MY_IP=$(curl -s ifconfig.me)

# Get security group ID
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=ElasticMapReduce-master" \
  --query 'SecurityGroups[0].GroupId' --output text --region ap-southeast-1)

# Add SSH rule
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID --protocol tcp --port 22 \
  --cidr $MY_IP/32 --region ap-southeast-1

# Add Jupyter rule
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID --protocol tcp --port 8192 \
  --cidr $MY_IP/32 --region ap-southeast-1
```

### Step 5: Access Jupyter Lab

**Get master node IP:**
```bash
# Method 1: AWS CLI
aws emr list-instances --cluster-id <cluster-id> \
  --instance-group-types MASTER \
  --query 'Instances[0].PublicIpAddress' --output text \
  --region ap-southeast-1

# Method 2: Check Master public DNS in EMR console

# Method 3: Check instance with MASTER tag in EC2 console
```

**Access URL:** `http://<master-ip>:8192`
- No password (token authentication disabled)

## Key Script Descriptions

### bootstrap_python.sh
Sets up Python 3.11 environment and installs required packages.

```bash
# Use dnf on Amazon Linux 2023
sudo dnf install -y python3.11 python3.11-pip python3.11-devel

# Install required packages
sudo /usr/bin/python3.11 -m pip install \
  jupyterlab ipywidgets pandas matplotlib seaborn bokeh
```

### hail_build.sh
Installs Hail from PyPI and configures Java 11.

Key tasks:
1. Set Java 11 environment variables
2. Change Spark's Java setting from Java 17 → Java 11
3. Install Hail from PyPI: `pip install hail`

### jupyter_run.sh
Starts Jupyter Lab and configures Spark integration.

Key settings:
```bash
# Specify Python version
export PYSPARK_PYTHON=/usr/bin/python3.11
export PYSPARK_DRIVER_PYTHON=/usr/bin/python3.11

# Java 11 setting
export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64

# Hail JAR path (PyPI installation priority)
HAIL_JAR=$(find /usr/local/lib/python3.11/site-packages/hail \
  -name "hail-all-spark.jar" 2>/dev/null | head -1)
```

### install_hail.sh
Orchestrates the entire installation process on the master node.

## Troubleshooting

### 1. ClassNotFoundException: is.hail.kryo.HailKryoRegistrator

**Cause:** Hail JAR file not found or version mismatch

**Solution:**
```bash
# Check Hail JAR location
find /usr/local/lib/python3.11/site-packages/hail -name "*.jar"

# Restart Jupyter
cd /opt/hail-on-AWS-spot-instances/src && ./jupyter_run.sh
```

### 2. UnsupportedClassVersionError

**Cause:** Using Java 17 (Hail requires Java 11)

**Solution:**
```bash
# Check Java version
java -version

# Check Spark configuration file
cat /etc/spark/conf/spark-env.sh | grep JAVA

# Change to Java 11
export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64
```

### 3. ModuleNotFoundError: No module named 'hail'

**Cause:** Using wrong Python version

**Solution:**
```bash
# Use correct Python
python3.11 -c "import hail as hl; print(hl.__version__)"

# Verify Python 3.11 kernel in Jupyter
```

### 4. bokeh AttributeError

**Cause:** Compatibility issue with bokeh 3.x

**Solution:** Modify import statement in plotting.py
```python
# Before
from bokeh.plotting import figure, show, output_file
# After
from bokeh.plotting import figure, show, output_file, Figure
```

### 5. EMR Cluster Creation Failure

**Cause:** Missing IAM roles or insufficient permissions

**Solution:**
```bash
# Create default roles
aws emr create-default-roles

# Verify roles
aws iam get-role --role-name EMR_DefaultRole
aws iam get-role --role-name EMR_EC2_DefaultRole
```

## IAM Roles and Policies

### EMR Service Roles

| Role | Policy | Purpose |
|------|--------|---------|
| EMR_DefaultRole | AmazonEMRServicePolicy_v2 | EMR service role |
| EMR_EC2_DefaultRole | AmazonElasticMapReduceforEC2Role | EC2 instance role |
| EMR_AutoScaling_DefaultRole | AmazonElasticMapReduceforAutoScalingRole | Auto Scaling role |

### Minimum IAM User Permissions

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticmapreduce:RunJobFlow",
                "elasticmapreduce:DescribeCluster",
                "elasticmapreduce:ListClusters",
                "elasticmapreduce:TerminateJobFlows"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeSecurityGroups",
                "ec2:AuthorizeSecurityGroupIngress"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::your-bucket",
                "arn:aws:s3:::your-bucket/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": [
                "arn:aws:iam::*:role/EMR_DefaultRole",
                "arn:aws:iam::*:role/EMR_EC2_DefaultRole"
            ]
        }
    ]
}
```

## S3 Bootstrap Script Locations

Scripts used in current deployment:
```
s3://hail-test-bucket-ap-southeast-1/hail_bootstrap/
├── bootstrap_python.sh
├── hail_build.sh
├── install_hail.sh
└── jupyter_run.sh
```

## Useful Commands

```bash
# Check cluster status
aws emr describe-cluster --cluster-id <cluster-id> --region <region>

# Check installation logs (on master node)
tail -f /tmp/cloudcreation_log.out

# Check Hail version
python3.11 -c "import hail as hl; print(hl.__version__)"

# Restart Jupyter
cd /opt/hail-on-AWS-spot-instances/src && ./jupyter_run.sh

# Terminate cluster
aws emr terminate-clusters --cluster-ids <cluster-id> --region <region>
```

## Version Compatibility Notes

### Python Package Dependencies (Hail 0.2.137+)

Hail 0.2.137 requires the following Python package versions:

| Package | Required Version | Notes |
|---------|-----------------|-------|
| NumPy | >=2.0, <3.0 | Version 1.x not supported |
| pandas | >=2.0, <3.0 | |
| scipy | >1.13, <2.0 | |
| bokeh | >=3.0, <3.5 | Visualization library |
| PySpark | >=3.5.0, <3.6 | Included in EMR 7.12.0 |

These dependencies are automatically resolved when installing Hail via PyPI.

### Deprecated API (0.2.137+)

Starting from Hail 0.2.137, `hl.hadoop_*` functions are deprecated. Use `hailtop.fs` instead:

```python
# Deprecated (prints warning message)
import hail as hl
hl.hadoop_ls('s3://bucket/')
hl.hadoop_copy('source', 'dest')
hl.hadoop_exists('s3://path')

# Recommended alternative
import hailtop.fs as hfs
hfs.ls('s3://bucket/')
hfs.copy('source', 'dest')
hfs.exists('s3://path')
```

### File Format Compatibility

- **Hail 0.2.119+** uses **Zstandard** compression by default (~20% file size reduction)
- Native file format version: **1.7.0**
- Tables/MatrixTables written with Hail 0.2.119+ **cannot be read by earlier versions**

If you need to share data with users of earlier versions, export to VCF or other portable formats.

### Version History Summary

| Version | Major Changes |
|---------|---------------|
| 0.2.137 | `hl.hadoop_*` deprecated, gamma distribution functions added |
| 0.2.136 | Default Python version upgraded to 3.11, Python <=3.9 support dropped |
| 0.2.131 | Spark 3.5.0, Java 11 official support |
| 0.2.119 | Zstandard compression default, file format 1.7.0 |

## References

- [Hail Official Documentation](https://hail.is/docs/0.2/index.html)
- [Hail Change Log](https://hail.is/docs/0.2/change_log.html)
- [AWS EMR Documentation](https://docs.aws.amazon.com/emr/latest/ManagementGuide/)
- [Spark 3.5 Documentation](https://spark.apache.org/docs/3.5.0/)

---

*This document is based on actual EMR 7.12.0 cluster deployment and testing results from March 2026.*
