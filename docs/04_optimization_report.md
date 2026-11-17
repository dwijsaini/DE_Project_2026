# CP3 optimization report — draft

> **Status: waiting for CP2 baseline evidence.** The current DE checkout does not contain `benchmarks/results/baseline/summary.csv` or the per-query baseline plan files. The local PostgreSQL service was stopped when this draft was prepared, so baseline plans could not be generated here. No timing values or plan bottlenecks have been guessed. Do not treat this draft as the completed CP3 report.

## Optimization results

Populate this table from the actual CP2 and CP3 benchmark outputs. Keep the original workload at `queries/workload_30.sql` unchanged. For each changed query, verify that the optimized result matches the original; separately document any correction to the NULL-related wrong answer required by the project instructions.

| Query | Before (ms) | Problem found in baseline plan | Optimization applied | After (ms) | Improvement | Same result? |
|---|---:|---|---|---:|---:|:---:|
| R01 | | | | | | |
| R02 | | | | | | |
| R03 | | | | | | |
| R04 | | | | | | |
| R05 | | | | | | |
| R06 | | | | | | |
| R07 | | | | | | |
| R08 | | | | | | |
| R09 | | | | | | |
| R10 | | | | | | |
| R11 | | | | | | |
| R12 | | | | | | |
| R13 | | | | | | |
| R14 | | | | | | |
| R15 | | | | | | |
| R16 | | | | | | |
| R17 | | | | | | |
| R18 | | | | | | |
| R19 | | | | | | |
| R20 | | | | | | |
| R21 | | | | | | |
| R22 | | | | | | |
| R23 | | | | | | |
| R24 | | | | | | |
| R25 | | | | | | |
| W01 | | | | | | |
| W02 | | | | | | |
| W03 | | | | | | |
| W04 | | | | | | |
| W05 | | | | | | |
| **Total** | | | | | | |

## Required supporting evidence — pending

- CP2: `benchmarks/results/baseline/summary.csv` and all 30 raw plan files.
- CP3: `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, and `benchmarks/results/optimized/summary.csv` with raw plans.
- Equivalence checks for rewritten queries; explain any NULL-semantics correction separately.
- Before/after plans for the five largest measured improvements.
- Measured write-query overhead and storage size of each added index.
- A short explanation for queries that did not improve.

When timing results are available, calculate improvement as `(before - after) / before * 100`. Copy reported numbers from the benchmark outputs; do not fill this draft with estimated or sample values.
