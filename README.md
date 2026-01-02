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

Ensure the following EMR service roles exist in your AWS account:
- `EMR_DefaultRole`
- `EMR_EC2_DefaultRole`
- `EMR_AutoScaling_DefaultRole`

If these roles don't exist, create them with:
```bash
aws emr create-default-roles
```

## How to Use This CloudFormation Tool

### Step 1: Clone the Repository

```bash
git clone https://github.com/hms-dbmi/hail-on-AWS-spot-instances
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

#### Spot Instance Pricing

To find competitive bid prices for spot instances:

1. Go to the [EMR Console](https://console.aws.amazon.com/elasticmapreduce)
2. Click **Create cluster** > **Go to advanced options**
3. In Step 2 (Hardware), select your desired instance type
4. Check current spot prices for your availability zone
5. Set `WORKER_BID_PRICE` slightly above the current price

**Tip:** Prices vary by availability zone. Choose a zone with lower prices when possible.

#### Subnet Configuration

Find your subnet ID in the [VPC Console](https://console.aws.amazon.com/vpc) under **Subnets**. Leave blank to use the default subnet.

#### Security Groups

If left empty, EMR creates default security groups. To use existing groups:

1. Go to [VPC Console](https://console.aws.amazon.com/vpc) > **Security Groups**
2. Ensure your master security group has these inbound rules:
   - Port **22** (SSH)
   - Port **8192** (Jupyter Lab)

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

1. Open your browser and navigate to `http://<master-ip>:8192`
2. Enter password: **`avillach`**

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

### Useful Commands

```bash
# SSH to master node
ssh -i /path/to/key.pem hadoop@<master-dns>

# Check installation logs
tail -f /tmp/cloudcreation_log.out

# Check Hail installation
python3 -c "import hail as hl; print(hl.__version__)"

# Restart Jupyter Lab
cd /opt/hail-on-AWS-spot-instances/src && ./jupyter_run.sh
```

## Resources

- [Hail Documentation](https://hail.is/docs/0.2/index.html)
- [AWS EMR Documentation](https://docs.aws.amazon.com/emr/latest/ManagementGuide/)
- [Spark Documentation](https://spark.apache.org/docs/3.5.0/)

## License

This project is licensed under the MIT License.
