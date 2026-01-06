# Hail on Amazon EMR: CloudFormation Tool with Spot Instances

This CloudFormation tool (macOS and Linux compatible) creates an **EMR 7.5.0** cluster with **Spark 3.5.x**, using [spot instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html) for cost-effective cluster deployment. Once your cluster is up and running, it will have the latest [**Hail 0.2**](https://www.hail.is) version and **Jupyter Lab** installed.

## Version Information

| Component | Version |
|-----------|---------|
| EMR | 7.5.0 |
| Spark | 3.5.x |
| Hail | 0.2.137+ (latest) |
| Python | 3.11 |
| Java | 11 (Amazon Corretto) |
| Operating System | Amazon Linux 2023 |

## Software Requirements

This tool requires the following programs to be installed on your computer:

* Python 3.10+ with pip
* AWS Command Line Interface (CLI) v2
* Required Python libraries: boto3, pandas, botocore, paramiko, pyyaml

### Installation Instructions

#### For macOS

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Python 3.11
brew install python@3.11

# Upgrade pip
python3 -m pip install --upgrade pip

# Install required libraries
python3 -m pip install boto3 pandas botocore paramiko pyyaml

# Install AWS CLI v2
brew install awscli
```

#### For Ubuntu/Debian

```bash
# Update package list
sudo apt-get update

# Install Python 3.11 and pip
sudo apt-get install -y python3.11 python3.11-venv python3-pip

# Upgrade pip
python3 -m pip install --upgrade pip

# Install required libraries
python3 -m pip install boto3 pandas botocore paramiko pyyaml

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

#### For Amazon Linux 2023

```bash
# Install Python packages
sudo dnf install -y python3.11 python3.11-pip

# Install required libraries
python3 -m pip install boto3 pandas botocore paramiko pyyaml

# AWS CLI is pre-installed on Amazon Linux 2023
```

## Before Getting Started

This tool uses Amazon's CLI utility. Before starting, ensure you have:

### a) Configured AWS CLI Account

From the terminal, execute `aws configure`. For additional information, see the [AWS CLI Configuration Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html).

If your CLI account has been previously configured, the tool will use that configuration by default. To reconfigure or use a different account/user, run `aws configure` again.

### b) Valid EC2 Key Pair

You need an EC2 key pair to SSH into your cluster. See [Amazon EC2 Key Pairs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html) to learn how to create and use your key.

**Security Note:** Set proper permissions for your key file:
```bash
chmod 400 my-key.pem
```

### c) Required IAM Roles

EMR requires specific IAM roles for cluster operation. The easiest way to create them is:

```bash
aws emr create-default-roles
```

This creates the following roles with AWS managed policies:

| Role | Policy | Purpose |
|------|--------|---------|
| `EMR_DefaultRole` | `AmazonEMRServicePolicy_v2` | EMR service role for provisioning resources |
| `EMR_EC2_DefaultRole` | `AmazonElasticMapReduceforEC2Role` | Role for EC2 instances in the cluster |
| `EMR_AutoScaling_DefaultRole` | `AmazonElasticMapReduceforAutoScalingRole` | Role for auto-scaling operations |

#### IAM User Permissions

Your IAM user (used with `aws configure`) needs the following permissions:

**Option 1: AWS Managed Policy (Recommended for testing)**
- `AmazonEMRFullAccessPolicy_v2` - Full EMR access
- `AmazonS3FullAccess` - S3 access for logs and data
- `AmazonEC2FullAccess` - EC2 access for instances

**Option 2: Custom Policy (Recommended for production)**

Create a custom IAM policy with minimum required permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EMRAccess",
            "Effect": "Allow",
            "Action": [
                "elasticmapreduce:RunJobFlow",
                "elasticmapreduce:DescribeCluster",
                "elasticmapreduce:ListClusters",
                "elasticmapreduce:ListInstances",
                "elasticmapreduce:TerminateJobFlows",
                "elasticmapreduce:AddJobFlowSteps"
            ],
            "Resource": "*"
        },
        {
            "Sid": "EC2Access",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcs",
                "ec2:DescribeKeyPairs"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3Access",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::your-bucket-name",
                "arn:aws:s3:::your-bucket-name/*"
            ]
        },
        {
            "Sid": "IAMPassRole",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": [
                "arn:aws:iam::*:role/EMR_DefaultRole",
                "arn:aws:iam::*:role/EMR_EC2_DefaultRole",
                "arn:aws:iam::*:role/EMR_AutoScaling_DefaultRole"
            ]
        }
    ]
}
```

Verify roles exist:
```bash
aws iam get-role --role-name EMR_DefaultRole
aws iam get-role --role-name EMR_EC2_DefaultRole
```

## How to Use This CloudFormation Tool

### Step 1: Clone the Repository

```bash
git clone -b dev https://github.com/hmkim/hail-on-AWS-spot-instances
cd hail-on-AWS-spot-instances/src
```

### Step 2: Configure Your Cluster

Edit the configuration file `config_EMR_spot.yaml` with your preferred text editor:

```yaml
config:
  EMR_CLUSTER_NAME: "my-hail-02-cluster"    # Name for your EMR cluster
  EMR_RELEASE_LABEL: "emr-7.5.0"            # EMR release version
  EC2_NAME_TAG: "my-hail-EMR"               # Tag for EC2 instances
  OWNER_TAG: "emr-owner"                    # Owner tag
  PROJECT_TAG: "my-project"                 # Project tag
  REGION: "us-east-1"                       # AWS region
  MASTER_INSTANCE_TYPE: "m6i.xlarge"        # Master node instance type (xlarge minimum)
  WORKER_INSTANCE_TYPE: "r6i.4xlarge"       # Worker node instance type
  WORKER_COUNT: "4"                         # Number of worker nodes
  WORKER_BID_PRICE: "0.50"                  # Max bid price for spot instances
  MASTER_HD_SIZE: "50"                      # Master storage in GB
  WORKER_HD_SIZE: "150"                     # Worker storage in GB
  SUBNET_ID: ""                             # VPC subnet (optional)
  S3_BUCKET: "s3://my-s3-bucket/"           # S3 bucket for EMR logs
  KEY_NAME: "my-key"                        # EC2 key pair name (without .pem)
  PATH_TO_KEY: "/full-path-to/my-key/"      # Path to key file directory
  WORKER_SECURITY_GROUP: ""                 # Worker security group (optional)
  MASTER_SECURITY_GROUP: ""                 # Master security group (optional)
  HAIL_VERSION: "current"                   # Hail version (git hash or "current")
```

### Configuration Details

#### Instance Types

**Recommended instance types for EMR 7.x:**

> **Important:** EMR 7.5.0 requires **xlarge or larger** instance types. Smaller instance types (large, medium, small) are not supported.

| Role | Recommended Types | Notes |
|------|-------------------|-------|
| Master | m6i.xlarge, m5.xlarge | General purpose, cost-effective (xlarge minimum required) |
| Worker | r6i.2xlarge, r6i.4xlarge | Memory optimized for genomics |
| Worker (alt) | m6i.4xlarge, c6i.4xlarge | Compute/general purpose |

View all instance types at [AWS EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/).

#### Subnet Configuration

Find your subnet ID in the [VPC Console](https://console.aws.amazon.com/vpc) under **Subnets**. Leave blank to use the default subnet.

#### Security Groups

If left empty, EMR creates default security groups. After cluster creation, you need to add inbound rules to access the cluster from your computer.

**Adding inbound rules to the Master security group:**

1. Go to [EC2 Console](https://console.aws.amazon.com/ec2) > **Security Groups**
2. Find the security group named `ElasticMapReduce-master` (or your custom master security group)
3. Click **Edit inbound rules** and add:

| Type | Port | Source | Description |
|------|------|--------|-------------|
| SSH | 22 | My IP | SSH access |
| Custom TCP | 8192 | My IP | Jupyter Lab |

**Finding your IP address:**
```bash
curl -s ifconfig.me
```

**Using AWS CLI to add rules:**
```bash
# Get your public IP
MY_IP=$(curl -s ifconfig.me)

# Find the master security group ID (after cluster is created)
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=ElasticMapReduce-master" --query 'SecurityGroups[0].GroupId' --output text --region <your-region>)

# Add SSH rule
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr $MY_IP/32 --region <your-region>

# Add Jupyter Lab rule
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 8192 --cidr $MY_IP/32 --region <your-region>
```

See [EMR Security Groups](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-security-groups.html) for more details.

#### Hail Version

- `"current"` - Installs the latest Hail version from the main branch
- Git hash (7-40 characters) - Installs a specific Hail version

### Step 3: Deploy the Cluster

From the `src` directory, run:

```bash
sh cloudformation_hail_spot.sh
```

The cluster creation takes approximately **10-15 minutes**. The script will output:
- Cluster ID
- Master node IP address
- Jupyter Lab URL (e.g., `http://123.456.0.1:8192`)

**Do not terminate the script** - it automatically provides connection information.

### Step 4: Monitor Cluster Status

Check cluster status at the [EMR Console](https://console.aws.amazon.com/elasticmapreduce). The cluster is ready when status shows **Waiting** with a green indicator.

After the cluster is created, allow **10-15 minutes** for Hail installation and configuration. Monitor progress by SSHing to the master node:

```bash
ssh -i /path/to/your-key.pem hadoop@<master-dns>
tail -f /tmp/cloudcreation_log.out
```

## Launching Jupyter Lab

### Finding the Master Node IP Address

**Option 1: Using AWS CLI**
```bash
# Replace <cluster-id> and <region> with your values
aws emr describe-cluster --cluster-id <cluster-id> --region <region> --query 'Cluster.MasterPublicDnsName' --output text

# Or get the public IP directly
aws emr list-instances --cluster-id <cluster-id> --instance-group-types MASTER --region <region> --query 'Instances[0].PublicIpAddress' --output text
```

**Option 2: Using EMR Console**
1. Go to [EMR Console](https://console.aws.amazon.com/elasticmapreduce)
2. Click on your cluster name
3. Find **Master public DNS** in the Summary tab

**Option 3: Using EC2 Console**
1. Go to [EC2 Console](https://console.aws.amazon.com/ec2) > **Instances**
2. Find the instance with tag `Name: <your-cluster-name>` and `aws:elasticmapreduce:instance-group-role: MASTER`
3. Copy the **Public IPv4 address**

### Accessing Jupyter Lab

1. Open your browser and navigate to `http://<master-ip>:8192`
2. No password required (token authentication is disabled)

You're now ready to use Hail!

## Sample Notebooks

The `notebook/` directory contains sample Jupyter notebooks including a GWAS tutorial to help you get started with Hail.

## Troubleshooting

### Common Issues

**"variable cluster_id_json is out of range" error:**
- Check your AWS CLI configuration (`aws configure`)
- Verify your IAM user has EMR permissions (AmazonElasticMapReduceFullAccess)
- Run `aws emr create-default-roles` to create required IAM roles

**"EMR_DefaultRole is invalid" error:**
- Create default roles: `aws emr create-default-roles`
- See [AWS Knowledge Center](https://aws.amazon.com/premiumsupport/knowledge-center/emr-default-role-invalid/)

**Hail ClassNotFoundException errors:**
```java
FatalError: ClassNotFoundException: is.hail.kryo.HailKryoRegistrator
```
This can occur when spot instances are replaced. The tool automatically detects and fixes this (runs every minute via cron). You can also restart the Jupyter kernel: **Kernel** > **Restart**.

**Jupyter Lab not accessible:**
- Verify port 8192 is open in your master security group
- Check that the cluster status is "Waiting"
- Wait for installation to complete (check `/tmp/cloudcreation_log.out`)

**ModuleNotFoundError: No module named 'pandas' (or other modules):**
```python
ModuleNotFoundError: No module named 'pandas'
```
This error occurs when using the wrong Python version. Hail is installed on Python 3.11, not the system Python 3.9.

**Wrong:**
```bash
python3 -c "import hail as hl; print(hl.__version__)"
```

**Correct:**
```bash
python3.11 -c "import hail as hl; print(hl.__version__)"
```

### Useful Commands

```bash
# SSH to master node
ssh -i /path/to/key.pem hadoop@<master-dns>

# Check installation logs
tail -f /tmp/cloudcreation_log.out

# Check Hail installation (IMPORTANT: use python3.11, not python3)
python3.11 -c "import hail as hl; print(hl.__version__)"

# Restart Jupyter Lab
cd /opt/hail-on-AWS-spot-instances/src && ./jupyter_run.sh
```

**Important:** Hail is installed on Python 3.11, not the system Python 3.9. Always use `python3.11` when running Hail commands directly.

## Version Compatibility Notes

### Python Dependencies (Hail 0.2.137+)

Hail 0.2.137 requires specific versions of key Python packages:

| Package | Required Version |
|---------|------------------|
| NumPy | ≥2.0, <3.0 |
| pandas | ≥2.0, <3.0 |
| scipy | >1.13, <2.0 |
| bokeh | ≥3.0, <3.5 |
| PySpark | ≥3.5.0, <3.6 |

These dependencies are automatically installed when installing Hail via PyPI (`pip install hail`).

### Deprecated APIs (0.2.137+)

Starting from Hail 0.2.137, `hl.hadoop_*` functions are deprecated. Use `hailtop.fs` instead:

```python
# Deprecated (will show warnings)
import hail as hl
hl.hadoop_ls('s3://bucket/')
hl.hadoop_copy('source', 'dest')
hl.hadoop_exists('s3://path')

# Recommended replacement
import hailtop.fs as hfs
hfs.ls('s3://bucket/')
hfs.copy('source', 'dest')
hfs.exists('s3://path')
```

### File Format Compatibility

- **Hail 0.2.119+** uses **Zstandard** compression by default (~20% smaller files)
- Native file format version: **1.7.0**
- Tables/MatrixTables written with Hail 0.2.119+ **cannot be read by earlier versions**

If you need to share data with users on older Hail versions, consider exporting to VCF or other portable formats.

## Resources

- [Hail Documentation](https://hail.is/docs/0.2/index.html)
- [AWS EMR Documentation](https://docs.aws.amazon.com/emr/latest/ManagementGuide/)
- [Spark Documentation](https://spark.apache.org/docs/3.5.0/)

## License

This project is licensed under the MIT License.
