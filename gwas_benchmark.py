#!/usr/bin/env python3
"""
GWAS Tutorial Benchmark Script
Based on Hail's official GWAS tutorial
https://hail.is/docs/0.2/tutorials/01-genome-wide-association-study.html
"""

import time
import sys

# Record start time
total_start = time.time()

print("=" * 60)
print("GWAS Benchmark - Hail 0.2.137")
print("=" * 60)

# Step 1: Initialize Hail
print("\n[Step 1] Initializing Hail...")
step_start = time.time()

import hail as hl
hl.init()

print(f"  Hail initialized in {time.time() - step_start:.2f} seconds")
print(f"  Hail version: {hl.version()}")

# Step 2: Download 1KG data
print("\n[Step 2] Downloading 1000 Genomes data...")
step_start = time.time()

hl.utils.get_1kg('data/')

print(f"  Data downloaded in {time.time() - step_start:.2f} seconds")

# Step 3: Load MatrixTable
print("\n[Step 3] Loading MatrixTable...")
step_start = time.time()

mt = hl.read_matrix_table('data/1kg.mt/')

# Repartition for better parallelism
CPU = 4
nodes = 2  # 2 worker nodes
mt = mt.repartition(4 * CPU * nodes)

sample_count = mt.count_cols()
variant_count = mt.count_rows()

print(f"  Loaded in {time.time() - step_start:.2f} seconds")
print(f"  Samples: {sample_count}, Variants: {variant_count}")

# Step 4: Load phenotype annotations
print("\n[Step 4] Loading phenotype annotations...")
step_start = time.time()

table = hl.import_table('data/1kg_annotations.txt', impute=True).key_by('Sample')
mt = mt.annotate_cols(pheno=table[mt.s])

print(f"  Annotations loaded in {time.time() - step_start:.2f} seconds")

# Step 5: Variant QC
print("\n[Step 5] Performing Variant QC...")
step_start = time.time()

mt = hl.variant_qc(mt)
mt = mt.filter_rows(mt.variant_qc.p_value_hwe > 1e-6)

print(f"  Variant QC completed in {time.time() - step_start:.2f} seconds")
print(f"  Variants after HWE filter: {mt.count_rows()}")

# Step 6: Sample QC
print("\n[Step 6] Performing Sample QC...")
step_start = time.time()

mt = hl.sample_qc(mt)
mt = mt.filter_cols((mt.sample_qc.dp_stats.mean >= 4) & (mt.sample_qc.call_rate >= 0.97))

print(f"  Sample QC completed in {time.time() - step_start:.2f} seconds")
print(f"  Samples after QC: {mt.count_cols()}")

# Step 7: Genotype QC (allele balance filter)
print("\n[Step 7] Filtering by allele balance...")
step_start = time.time()

ab = mt.AD[1] / hl.sum(mt.AD)
filter_condition_ab = (
    (mt.GT.is_hom_ref() & (ab <= 0.1)) |
    (mt.GT.is_het() & (ab >= 0.25) & (ab <= 0.75)) |
    (mt.GT.is_hom_var() & (ab >= 0.9))
)
mt = mt.filter_entries(filter_condition_ab)

print(f"  Allele balance filter completed in {time.time() - step_start:.2f} seconds")

# Step 8: Singleton filter
print("\n[Step 8] Filtering singletons...")
step_start = time.time()

stats_singleton = mt.aggregate_cols(hl.agg.stats(mt.sample_qc.n_singleton))
mt = mt.filter_cols(mt.sample_qc.n_singleton < (stats_singleton.mean + (3 * stats_singleton.stdev)))
mt = mt.filter_cols(mt.sample_qc.n_singleton > (stats_singleton.mean - (3 * stats_singleton.stdev)))

print(f"  Singleton filter completed in {time.time() - step_start:.2f} seconds")

# Step 9: PCA for population stratification
print("\n[Step 9] Running PCA for population stratification...")
step_start = time.time()

mt_common = mt.filter_rows(mt.variant_qc.AF[1] > 0.05)
eigenvalues, scores, loadings = hl.hwe_normalized_pca(mt_common.GT, k=10, compute_loadings=True)
mt = mt.annotate_cols(scores=scores[mt.s].scores)

print(f"  PCA completed in {time.time() - step_start:.2f} seconds")
print(f"  Top 3 eigenvalues: {eigenvalues[:3]}")

# Step 10: Linear Regression (GWAS)
print("\n[Step 10] Running Linear Regression (GWAS)...")
step_start = time.time()

gwas = hl.linear_regression_rows(
    y=mt.pheno.CaffeineConsumption,
    x=mt.GT.n_alt_alleles(),
    covariates=[
        1, mt.pheno.isFemale,
        mt.scores[0], mt.scores[1], mt.scores[2],
        mt.scores[3], mt.scores[4], mt.scores[5],
        mt.scores[6], mt.scores[7], mt.scores[8],
        mt.scores[9]
    ]
)

print(f"  GWAS completed in {time.time() - step_start:.2f} seconds")

# Step 11: Get top hits
print("\n[Step 11] Identifying top hits...")
step_start = time.time()

gwas_ordered = gwas.order_by(gwas.p_value)
top_hits = gwas_ordered.take(10)

print(f"  Top hits identified in {time.time() - step_start:.2f} seconds")

print("\n" + "=" * 60)
print("TOP 10 GWAS HITS")
print("=" * 60)
for i, hit in enumerate(top_hits, 1):
    print(f"{i}. {hit.locus} - p-value: {hit.p_value:.2e}, beta: {hit.beta:.4f}")

# Calculate total time
total_time = time.time() - total_start

print("\n" + "=" * 60)
print("BENCHMARK SUMMARY")
print("=" * 60)
print(f"Total execution time: {total_time:.2f} seconds ({total_time/60:.2f} minutes)")
print(f"Final dataset: {mt.count_cols()} samples, {mt.count_rows()} variants")
print("=" * 60)

# Save summary to file
with open('/tmp/gwas_benchmark_result.txt', 'w') as f:
    f.write(f"Total execution time: {total_time:.2f} seconds\n")
    f.write(f"Samples: {mt.count_cols()}\n")
    f.write(f"Variants: {mt.count_rows()}\n")

hl.stop()
print("\nGWAS benchmark completed successfully!")
