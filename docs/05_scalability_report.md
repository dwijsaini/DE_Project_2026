# CP4 scalability report — large dataset

## Dataset and method

The supplied `large_data/` CSVs were loaded locally into a new PostgreSQL 18.7 database (`gpay_large`) using `sql/01_schema.sql` and `sql/02_load_data.sql` with only the folder path changed from `seed_data/` to `large_data/`. To reproduce the load from the repo root:

```sh
sed 's/seed_data/large_data/g' sql/02_load_data.sql > /tmp/02_load_large_data.sql
createdb gpay_large
psql -v ON_ERROR_STOP=1 -d gpay_large -f sql/01_schema.sql -f /tmp/02_load_large_data.sql
psql -v ON_ERROR_STOP=1 -d gpay_large -f sql/05_indexes.sql
./benchmarks/run_benchmark.sh gpay_large large 3 sql/06_optimized_queries.sql
```

`large_data/` is ignored by Git and the CSVs are not part of the commit. The source files were not edited. PostgreSQL was using the `Asia/Kolkata` session timezone, matching the date-based workload.

The large timings below use the optimized queries from `sql/06_optimized_queries.sql`, after applying `sql/05_indexes.sql` and `ANALYZE`. The benchmark ran every query three times with `EXPLAIN (ANALYZE, BUFFERS)`; W queries ran inside `BEGIN`/`ROLLBACK`. Large run plans and the three-run averages are in [`../benchmarks/results/large/`](../benchmarks/results/large/). Seed optimized timings are in [`../benchmarks/results/optimized/summary.csv`](../benchmarks/results/optimized/summary.csv). No original unoptimized workload was run on the large database.

### Loaded row counts

| Table | Seed rows | Large rows | Scale |
|---|---:|---:|---:|
| cities | 10 | 10 | 1× |
| users | 40,000 | 800,000 | 20× |
| bank_accounts | 53,333 | 1,066,666 | 20× |
| vpas | 53,333 | 1,066,666 | 20× |
| merchants | 3,000 | 60,000 | 20× |
| transactions | 250,468 | 5,009,340 | 20× |
| rewards | 39,799 | 798,991 | 20.1× |
| bill_payments | 30,000 | 600,000 | 20× |
| disputes | 3,569 | 73,365 | 20.6× |

### Optimized query timings and targets

“Growth” is the large-data average divided by the optimized seed-data average. Targets follow the workload instructions in `README.md`.

| Query | Optimized seed (ms) | Optimized large (ms) | Growth | Target | Result |
|---|---:|---:|---:|---:|:---:|
| R01 | 0.117 | 0.330 | 2.82× | <5 ms | Pass |
| R02 | 0.128 | 0.152 | 1.19× | <5 ms | Pass |
| R03 | 0.048 | 0.210 | 4.38× | <5 ms | Pass |
| R04 | 0.060 | 0.443 | 7.38× | <5 ms | Pass |
| R05 | 0.117 | 0.245 | 2.09× | <250 ms | Pass |
| R06 | 0.489 | 8.926 | 18.25× | <5,000 ms | Pass |
| R07 | 4.385 | 50.227 | 11.45× | <5,000 ms | Pass |
| R08 | 45.385 | 1060.918 | 23.38× | <5,000 ms | Pass |
| R09 | 55.628 | 1341.914 | 24.12× | <5,000 ms | Pass |
| R10 | 0.046 | 0.019 | 0.41× | <5 ms | Pass |
| R11 | 0.052 | 0.111 | 2.13× | <250 ms | Pass |
| R12 | 0.047 | 0.021 | 0.45× | <5 ms | Pass |
| R13 | 1.354 | 29.335 | 21.67× | <250 ms | Pass |
| R14 | 0.150 | 0.303 | 2.02× | <250 ms | Pass |
| R15 | 3.041 | 83.835 | 27.57× | <5,000 ms | Pass |
| R16 | 0.169 | 6.211 | 36.75× | <250 ms | Pass |
| R17 | 9.121 | 99.808 | 10.94× | <5,000 ms | Pass |
| R18 | 17.935 | 338.156 | 18.85× | <5,000 ms | Pass |
| R19 | 10.435 | 114.124 | 10.94× | <5,000 ms | Pass |
| R20 | 2.107 | 52.449 | 24.89× | <5,000 ms | Pass |
| R21 | 0.257 | 3.606 | 14.03× | <250 ms | Pass |
| R22 | 0.037 | 0.208 | 5.62× | <5 ms | Pass |
| R23 | 38.892 | 40.404 | 1.04× | <250 ms | Pass |
| R24 | 0.206 | 0.158 | 0.77× | <5 ms | Pass |
| R25 | 13.519 | 166.604 | 12.32× | <5,000 ms | Pass |
| W01 | 1.196 | 1.661 | 1.39× | <5 ms | Pass |
| W02 | 0.485 | 1.056 | 2.18× | <5 ms | Pass |
| W03 | 0.353 | 0.050 | 0.14× | <5 ms | Pass |
| W04 | 0.395 | 2.766 | 7.00× | <1,000 ms | Pass |
| W05 | 1.590 | 116.471 | 73.25× | <1,000 ms | Pass |

**All 30 large-dataset averages met their listed target.** R08 and R09 remain the slowest reads at about 1.06 s and 1.34 s because they aggregate/window over millions of qualifying transaction rows, but both remain below the 5 s analytics target. W05's bulk overdue-bill update grew to about 116 ms and remains below the 1 s batch target. The largest relative growth is W05 (73.25×); its write cost tracks the increased number of rows updated.

R23 is a keyset-pagination design with a composite `(initiated_at DESC, txn_id DESC)` index. The standalone reproducible benchmark derives the page cursor with an `OFFSET 199999` CTE, so its measured 40.404 ms includes cursor discovery. A live client would send the last row's `(initiated_at, txn_id)` from the preceding page and avoid that offset scan. The deterministic transaction-ID tie-breaker also makes page boundaries stable when timestamps match.

## Integrity checks

- All nine CSVs loaded with their FK, unique, and CHECK constraints enabled. The loader completed and ran `ANALYZE`.
- Row counts matched the source files: 5,009,340 transactions, 800,000 users, 1,066,666 bank accounts and VPAs, 60,000 merchants, 798,991 rewards, 600,000 bills, 73,365 disputes, and 10 cities.
- The optimized workload completed for all 30 query IDs, three runs each. W01's test transaction (`txn_id=90000001`, `upi_ref=999900000001`) was absent after benchmarking; write tests use rollback.
- On the seed data, the optimized read outputs matched the originals for 24 of 25 reads. R13 is the documented correction: original output is empty due to NULL-sensitive `NOT IN`; corrected `NOT EXISTS` returns 450 merchants with no transaction.
- Git status confirms `large_data/` is ignored; CSV data is not staged. The counts and write-rollback check are also saved in [`../benchmarks/results/large/integrity.txt`](../benchmarks/results/large/integrity.txt).

## Growth analysis

Selective point lookups and user-scoped queries remain sub-millisecond at 20× scale (for example R01–R05, R10, R12, R14, R22, and R24). Their index seeks grow slowly with table size. Queries that aggregate broad date ranges or most matching rows grew closer to data volume: R08 23.38×, R09 24.12×, R15 27.57×, R20 24.89×. R19 grows 10.94× rather than 20× because the two correlated rescans were replaced with one grouped transaction scan. Smaller queries show noisy ratios because their times are close to the timer and cache floor.

No query exceeded its Phase 5 target. The main scale costs are global transaction analytics (R08/R09), the all-row merchant anti-join (R13), and batch updates. For these, partitioning, pre-aggregated summaries, and carefully scheduled batch work become more important as volume grows.

## Storage

Sizes were measured after all Phase 4 indexes were created. `Table bytes` and `index bytes` sum the nine base tables and their indexes; database size also includes PostgreSQL metadata and auxiliary files.

| Dataset | PostgreSQL database size | Table heap total | Index total |
|---|---:|---:|---:|
| Seed | 284 MB | 55 MB | 220 MB |
| Large | 5,588 MB | 1,099 MB | 4,481 MB |

The indexes occupy about 4.1× the large table heap. This read performance is costly in disk space and adds maintenance to writes. If the row count reached 100× the original seed (about 25 million transactions, roughly five times this large dataset), a simple linear estimate is about 5.4 GiB of table heaps and 21.9 GiB of indexes, before WAL, backups, bloat, and growth in other files. This is an estimate, not a measurement.

## Partitioning design and pruning test

`sql/08_partitioning.sql` defines a monthly RANGE partitioned replacement for `transactions` on `initiated_at`, with a DEFAULT partition. The large data spans Jan 2025 through Jun 2026; monthly partitions fit date-bounded reporting and allow old months to be detached or archived. On the test copy, all 5,009,340 rows were routed into the partitioned table. A June 2026 aggregate plan pruned 18 of 19 partitions and scanned only `transactions_p2026_06`; the captured plan and its 19.062 ms execution time are in [`../benchmarks/results/large/partition_pruning.txt`](../benchmarks/results/large/partition_pruning.txt). The temporary partitioned copy was dropped after the test, so the reported large database size excludes it.

PostgreSQL requires a partitioned table's PRIMARY KEY and UNIQUE constraints to include the partition key. The example therefore uses `(txn_id, initiated_at)` and `(upi_ref, initiated_at)`. This does not enforce global uniqueness of `txn_id` or `upi_ref` alone; a production design needs a separate global key registry or revised referencing keys before replacing the current table. Queries without an `initiated_at` constraint, especially R08/R09, cannot prune by month and still visit many partitions.

## 100× architecture plan

- **Partitioning:** use monthly RANGE partitions on `initiated_at`, create the next month ahead of time, and detach/archive old partitions. Confirm the primary-key and foreign-key redesign before rollout.
- **Sharding:** hash by payer user/VPA is a reasonable write-routing key, but P2P sends, recipient history, merchant reporting, and risk queries cross payer shards. Keep a globally addressable transaction ID and use asynchronous cross-shard aggregation or a separate analytics store; avoid claiming payer sharding makes payee queries local.
- **Read replicas and caching:** send reporting/analytics reads (R06–R21 and R25, subject to freshness needs) to a replica or summary tables. Keep payment writes and immediate status checks on the primary. Cache merchant name search and stable reference data; don't cache payment status beyond the product's freshness tolerance.
- **Maintenance:** run `ANALYZE` after bulk loads and meaningful data changes; tune autovacuum for the frequently updated transactions/rewards/bills tables; monitor index bloat; refresh daily/monthly summary tables; archive old partitions and test restore procedures.

## Conclusion

The supplied 20× dataset loaded and all measured Phase 5 query targets passed with the current indexes. The measured results support the course-scale demonstration, not a production capacity guarantee. At larger volume, the main risks are the 4.4 GB index footprint, global analytics that cannot prune, and global uniqueness constraints under partitioning; address these before moving toward 100× scale.
