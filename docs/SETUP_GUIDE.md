# Hail on AWS EMR 7.5.0 종합 설정 가이드

이 문서는 AWS EMR 7.5.0에서 Hail 0.2.137을 설정하는 전체 과정과 주요 고려사항을 정리합니다.

## 버전 정보

| 컴포넌트 | 버전 | 비고 |
|---------|------|------|
| EMR | 7.5.0 | Amazon Linux 2023 기반 |
| Spark | 3.5.x | EMR 7.5.0에 포함 |
| Hail | 0.2.137+ | PyPI에서 설치 |
| Python | 3.11 | Hail 전용 (시스템 Python 3.9와 별도) |
| Java | 11 (Amazon Corretto) | Hail 요구사항 |
| OS | Amazon Linux 2023 | yum → dnf |

## 핵심 요구사항

### 1. Java 11 필수

Hail 0.2.137은 Java 11을 요구합니다. EMR 7.x는 기본적으로 Java 17을 사용하므로 반드시 Java 11로 변경해야 합니다.

**증상 (Java 17 사용 시):**
```
java.lang.UnsupportedClassVersionError: is/hail/backend/service/Main has been compiled by a more recent version of the Java Runtime
```

**해결 방법 (hail_build.sh에서 적용됨):**
```bash
# Spark의 Java 설정을 Java 17에서 Java 11로 변경
sudo sed -i 's|JAVA17_HOME=/usr/lib/jvm/jre-17|JAVA11_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64|g' /etc/spark/conf/spark-env.sh
sudo sed -i 's|export JAVA_HOME=\$JAVA17_HOME|export JAVA_HOME=\$JAVA11_HOME|g' /etc/spark/conf/spark-env.sh
```

### 2. xlarge 이상 인스턴스 타입 필수

EMR 7.5.0은 xlarge 이상의 인스턴스 타입만 지원합니다.

| 역할 | 권장 타입 | 비고 |
|------|----------|------|
| Master | m6i.xlarge | 최소 xlarge 필수 |
| Worker | r6i.2xlarge, r6i.4xlarge | 메모리 최적화 권장 |

**지원하지 않는 타입:** large, medium, small

### 3. Python 3.11 사용

Hail은 Python 3.11에 설치됩니다. 시스템 Python (3.9)을 수정하면 안 됩니다.

**올바른 사용:**
```bash
python3.11 -c "import hail as hl; print(hl.__version__)"
```

**잘못된 사용:**
```bash
python3 -c "import hail as hl; print(hl.__version__)"  # 에러 발생
```

### 4. Hail JAR 경로

PyPI에서 설치한 Hail의 JAR 파일 위치:
```
/usr/local/lib/python3.11/site-packages/hail/backend/hail-all-spark.jar
```

jupyter_run.sh에서 이 경로를 우선적으로 찾도록 설정되어 있습니다.

## 배포 아키텍처

```
cloudformation_hail_spot.sh
    └── run.sh (AWS 자격증명 검증)
        └── EMR_deploy_and_install_spot.py (boto3로 EMR 클러스터 생성)
            └── Bootstrap Actions (S3에서 다운로드):
                ├── bootstrap_python.sh (Python 3.11 환경 설정)
                ├── install_hail.sh (마스터 노드 설정 오케스트레이션)
                │   ├── hail_build.sh (Hail PyPI 설치, Java 11 설정)
                │   └── jupyter_run.sh (Jupyter Lab 시작)
                └── run_when_new_instance_added.sh (스팟 인스턴스 복구용 cron)
```

## 배포 단계

### 1단계: 사전 준비

```bash
# AWS CLI 설정
aws configure

# EMR 기본 역할 생성
aws emr create-default-roles

# EC2 키 페어 권한 설정
chmod 400 my-key.pem
```

### 2단계: 설정 파일 수정

`src/config_EMR_spot.yaml`:
```yaml
config:
  EMR_CLUSTER_NAME: "my-hail-02-cluster"
  EMR_RELEASE_LABEL: "emr-7.5.0"
  REGION: "ap-northeast-2"
  MASTER_INSTANCE_TYPE: "m6i.xlarge"      # xlarge 이상 필수
  WORKER_INSTANCE_TYPE: "r6i.4xlarge"
  WORKER_COUNT: "4"
  WORKER_BID_PRICE: "0.50"
  S3_BUCKET: "s3://your-bucket/"
  KEY_NAME: "my-key"
  PATH_TO_KEY: "/path/to/key/"
  HAIL_VERSION: "current"
```

### 3단계: 클러스터 배포

```bash
cd src
sh cloudformation_hail_spot.sh
```

배포 소요 시간: 약 10-15분

### 4단계: 보안 그룹 설정

EMR 마스터 보안 그룹에 다음 인바운드 규칙 추가:

| 포트 | 용도 |
|------|------|
| 22 | SSH 접속 |
| 8192 | Jupyter Lab |

```bash
# 내 IP 확인
MY_IP=$(curl -s ifconfig.me)

# 보안 그룹 ID 확인
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=ElasticMapReduce-master" \
  --query 'SecurityGroups[0].GroupId' --output text --region ap-northeast-2)

# SSH 규칙 추가
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID --protocol tcp --port 22 \
  --cidr $MY_IP/32 --region ap-northeast-2

# Jupyter 규칙 추가
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID --protocol tcp --port 8192 \
  --cidr $MY_IP/32 --region ap-northeast-2
```

### 5단계: Jupyter Lab 접속

**마스터 노드 IP 확인:**
```bash
# 방법 1: AWS CLI
aws emr list-instances --cluster-id <cluster-id> \
  --instance-group-types MASTER \
  --query 'Instances[0].PublicIpAddress' --output text \
  --region ap-northeast-2

# 방법 2: EMR 콘솔에서 Master public DNS 확인

# 방법 3: EC2 콘솔에서 MASTER 태그가 있는 인스턴스 확인
```

**접속 URL:** `http://<master-ip>:8192`
- 비밀번호 없음 (토큰 인증 비활성화)

## 주요 스크립트 설명

### bootstrap_python.sh
Python 3.11 환경을 설정하고 필요한 패키지를 설치합니다.

```bash
# Amazon Linux 2023에서는 dnf 사용
sudo dnf install -y python3.11 python3.11-pip python3.11-devel

# 필수 패키지 설치
sudo /usr/bin/python3.11 -m pip install \
  jupyterlab ipywidgets pandas matplotlib seaborn bokeh
```

### hail_build.sh
Hail을 PyPI에서 설치하고 Java 11을 설정합니다.

핵심 작업:
1. Java 11 환경 변수 설정
2. Spark의 Java 설정을 Java 17 → Java 11로 변경
3. PyPI에서 Hail 설치: `pip install hail`

### jupyter_run.sh
Jupyter Lab을 시작하고 Spark 연동을 설정합니다.

핵심 설정:
```bash
# Python 버전 지정
export PYSPARK_PYTHON=/usr/bin/python3.11
export PYSPARK_DRIVER_PYTHON=/usr/bin/python3.11

# Java 11 설정
export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64

# Hail JAR 경로 (PyPI 설치 우선)
HAIL_JAR=$(find /usr/local/lib/python3.11/site-packages/hail \
  -name "hail-all-spark.jar" 2>/dev/null | head -1)
```

### install_hail.sh
마스터 노드에서 전체 설치 과정을 오케스트레이션합니다.

## 문제 해결

### 1. ClassNotFoundException: is.hail.kryo.HailKryoRegistrator

**원인:** Hail JAR 파일을 찾지 못함 또는 버전 불일치

**해결:**
```bash
# Hail JAR 위치 확인
find /usr/local/lib/python3.11/site-packages/hail -name "*.jar"

# Jupyter 재시작
cd /opt/hail-on-AWS-spot-instances/src && ./jupyter_run.sh
```

### 2. UnsupportedClassVersionError

**원인:** Java 17 사용 중 (Hail은 Java 11 필요)

**해결:**
```bash
# Java 버전 확인
java -version

# Spark 설정 파일 확인
cat /etc/spark/conf/spark-env.sh | grep JAVA

# Java 11로 변경
export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64
```

### 3. ModuleNotFoundError: No module named 'hail'

**원인:** 잘못된 Python 버전 사용

**해결:**
```bash
# 올바른 Python 사용
python3.11 -c "import hail as hl; print(hl.__version__)"

# Jupyter에서는 Python 3.11 커널 사용 확인
```

### 4. bokeh AttributeError

**원인:** bokeh 3.x와의 호환성 문제

**해결:** plotting.py에서 import 문 수정
```python
# Before
from bokeh.plotting import figure, show, output_file
# After
from bokeh.plotting import figure, show, output_file, Figure
```

### 5. EMR 클러스터 생성 실패

**원인:** IAM 역할 부재 또는 권한 부족

**해결:**
```bash
# 기본 역할 생성
aws emr create-default-roles

# 역할 확인
aws iam get-role --role-name EMR_DefaultRole
aws iam get-role --role-name EMR_EC2_DefaultRole
```

## IAM 역할 및 정책

### EMR 서비스 역할

| 역할 | 정책 | 용도 |
|------|------|------|
| EMR_DefaultRole | AmazonEMRServicePolicy_v2 | EMR 서비스 역할 |
| EMR_EC2_DefaultRole | AmazonElasticMapReduceforEC2Role | EC2 인스턴스 역할 |
| EMR_AutoScaling_DefaultRole | AmazonElasticMapReduceforAutoScalingRole | Auto Scaling 역할 |

### IAM 사용자 최소 권한

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

## S3 부트스트랩 스크립트 위치

현재 배포에 사용되는 스크립트:
```
s3://hail-test-bucket-ap-northeast-2/hail_bootstrap/
├── bootstrap_python.sh
├── hail_build.sh
├── install_hail.sh
└── jupyter_run.sh
```

## 유용한 명령어

```bash
# 클러스터 상태 확인
aws emr describe-cluster --cluster-id <cluster-id> --region <region>

# 설치 로그 확인 (마스터 노드에서)
tail -f /tmp/cloudcreation_log.out

# Hail 버전 확인
python3.11 -c "import hail as hl; print(hl.__version__)"

# Jupyter 재시작
cd /opt/hail-on-AWS-spot-instances/src && ./jupyter_run.sh

# 클러스터 종료
aws emr terminate-clusters --cluster-ids <cluster-id> --region <region>
```

## 참고 자료

- [Hail 공식 문서](https://hail.is/docs/0.2/index.html)
- [AWS EMR 문서](https://docs.aws.amazon.com/emr/latest/ManagementGuide/)
- [Spark 3.5 문서](https://spark.apache.org/docs/3.5.0/)

---

*이 문서는 2025년 1월 실제 EMR 7.5.0 클러스터 배포 및 테스트 결과를 바탕으로 작성되었습니다.*
