# Hail on AWS: Spot vs On-Demand Cost Analysis Report

## Execution Environment

- **Date**: 2026-01-06
- **Region**: ap-northeast-2 (Seoul)
- **EMR Version**: emr-7.5.0
- **Hail Version**: 0.2.137
- **Spark Version**: 3.5.x

## Cluster Configuration

### Common Specifications

| Component | Instance Type | Count | vCPU | Memory |
|-----------|--------------|-------|------|--------|
| Master | m5.xlarge | 1 | 4 | 16 GB |
| Worker | r5.2xlarge | 2 | 8 | 64 GB |

### Cluster IDs

| Cluster | ID | Master DNS | Status |
|---------|-----|-----------|--------|
| Spot | j-1A9KKKPR8ZWW8 | ec2-3-39-195-48.ap-northeast-2.compute.amazonaws.com | TERMINATED |
| On-Demand | j-1PK1W0OYZJWAQ | ec2-13-124-241-105.ap-northeast-2.compute.amazonaws.com | TERMINATED |

## Pricing Information (ap-northeast-2, as of 2026-01-06)

### On-Demand Pricing

| Instance Type | Hourly Price |
|--------------|--------------|
| m5.xlarge | $0.192 |
| r5.2xlarge | $0.608 |

### Spot Pricing (Average)

| Instance Type | Hourly Price | Savings |
|--------------|--------------|---------|
| m5.xlarge | ~$0.05 | ~74% |
| r5.2xlarge | ~$0.20 | ~67% |

## Hourly Cost Comparison

### Spot Cluster
```
Master (m5.xlarge x1, On-Demand):  $0.192/hr
Worker (r5.2xlarge x2, Spot):      $0.40/hr  (= $0.20 x 2)
─────────────────────────────────────────────
Total hourly cost:                 $0.592/hr
```

### On-Demand Cluster
```
Master (m5.xlarge x1):             $0.192/hr
Worker (r5.2xlarge x2):            $1.216/hr (= $0.608 x 2)
─────────────────────────────────────────────
Total hourly cost:                 $1.408/hr
```

## Cost Savings Analysis

| Period | Spot Cluster | On-Demand Cluster | Savings | Rate |
|--------|--------------|-------------------|---------|------|
| Hourly | $0.592 | $1.408 | $0.816 | **58%** |
| Daily (8 hours) | $4.74 | $11.26 | $6.53 | **58%** |
| Weekly (40 hours) | $23.68 | $56.32 | $32.64 | **58%** |
| Monthly (160 hours) | $94.72 | $225.28 | $130.56 | **58%** |

## GWAS Tutorial Execution Details

- **Jupyter Lab Access**:
  - Spot: http://3.39.195.48:8192
  - On-Demand: http://13.124.241.105:8192
  - Password: `avillach` (or token authentication disabled)

- **Tutorial Notebook**: `GWAS_tutorial_with_HMS_additions.ipynb`
- **Dataset**: 1000 Genomes Project sample data

## Spot Instance Considerations

### Advantages
1. **Cost Savings**: Up to 60-70% cost reduction
2. **Same Performance**: Identical computing performance to On-Demand
3. **EMR Integration**: Automatic Spot management by AWS EMR

### Disadvantages
1. **Interruption Risk**: AWS may reclaim instances when capacity is needed
2. **Price Volatility**: Spot prices vary by time and availability zone
3. **Availability Uncertainty**: Specific instance types may be unavailable

### Recommendations

| Workload Type | Recommended Option |
|---------------|-------------------|
| Development/Testing | Spot (cost-effective) |
| Batch Analysis | Spot (can restart on interruption) |
| Interactive Analysis | On-Demand (stability required) |
| Production Pipeline | On-Demand or Mixed |

## GWAS Benchmark Results

### Execution Environment
- Dataset: 1000 Genomes Project
- Sample Count: 249
- Variant Count: 9,653
- Analysis: Caffeine Consumption GWAS with 10 PCs

### Execution Time Comparison

| Cluster | Total Time | PCA Time | GWAS Time |
|---------|------------|----------|-----------|
| Spot | 100.37s | 41.96s | 10.91s |
| On-Demand | 108.18s | ~42s | 10.25s |

### Top GWAS Hits (Identical Results)
```
1. 8:19600329 - p-value: 8.25e-09, beta: 0.7532
2. 8:19651161 - p-value: 7.94e-08, beta: 0.6761
3. 8:19619751 - p-value: 1.10e-07, beta: 0.8636
4. 8:19826373 - p-value: 7.04e-06, beta: 0.6143
5. 8:19943027 - p-value: 1.30e-05, beta: 0.9194
```

### Cost Efficiency

| Item | Spot | On-Demand |
|------|------|-----------|
| Execution Cost (1.7 min) | ~$0.017 | ~$0.042 |
| Hourly Cost | $0.59 | $1.41 |
| **Savings Rate** | **60%** | - |

## Conclusion

Using Spot instances enables **approximately 60% cost savings**. GWAS benchmark results show virtually no performance difference between the two clusters, and analysis results are completely identical. For batch analysis workloads like GWAS, Spot instances are highly effective, and workflows can be restarted from checkpoints in case of interruption.

## Cluster Termination Commands

Terminate clusters after testing to save costs:

```bash
export AWS_PROFILE=664263524008_AdministratorAccess

# Terminate Spot cluster
aws emr terminate-clusters --cluster-ids j-1A9KKKPR8ZWW8 --region ap-northeast-2

# Terminate On-Demand cluster
aws emr terminate-clusters --cluster-ids j-1PK1W0OYZJWAQ --region ap-northeast-2
```
