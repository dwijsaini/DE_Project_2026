# CP4 scalability report — large dataset

> **Re-run note (25 November 2026):** The tables below use the final CP3 index set from `sql/05_indexes.sql`; the seed and large workloads were each run three times on PostgreSQL 18.7. Current raw plans and averages are in `benchmarks/results/optimized/` and `benchmarks/results/large/`.

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
| R01: Transaction history: everything user 15177 sent or received, newest first | 0.138 | 0.196 | 1.42× | < 5 ms | Pass |
| R02: "Pay to UPI ID": check that the entered VPA exists and is active | 0.035 | 0.090 | 2.57× | < 5 ms | Pass |
| R03: UPI limit check: total successfully sent by user 15177 on 30 June 2026 (limit ₹1,00,000/day) | 0.041 | 0.039 | 0.95× | < 5 ms | Pass |
| R04: Reconciliation: payments still PENDING more than 15 minutes after 23:59 on 30 Jun 2026 | 0.029 | 0.556 | 19.17× | < 5 ms | Pass |
| R05: Google Pay for Business: hourly collections of merchant 2 on 29 June 2026 | 0.055 | 0.068 | 1.24× | < 250 ms | Pass |
| R06: Settlement: amount to settle to every merchant for 29 June 2026 | 0.508 | 9.840 | 19.37× | < 5,000 ms | Pass |
| R07: Bank health: failure codes per payer bank in the last 7 days | 1.028 | 72.534 | 70.56× | < 5,000 ms | Pass |
| R08: Fraud: VPAs that received P2P money from 5+ different people on the same day | 137.824 | 1627.418 | 11.81× | < 5,000 ms | Pass |
| R09: Fraud: repeated payments—same payer to the same payee within 10 minutes of the previous one | 60.752 | 1332.751 | 21.94× | < 5,000 ms | Pass |
| R10: Rewards tab: user 15177's unscratched cards that have not expired | 0.037 | 0.098 | 2.65× | < 5 ms | Pass |
| R11: Notification job: unscratched rewards that expire in the first 3 days of July | 0.041 | 0.221 | 5.39× | < 250 ms | Pass |
| R12: Bill reminders: user 1072's unpaid bills due in the next 7 days | 0.024 | 0.053 | 2.21× | < 5 ms | Pass |
| R13: Merchant success team: merchants who have never received a payment (to call and help them) | 3.465 | 75.752 | 21.86× | < 250 ms | Pass |
| R14: Spend analysis: user 15177's 2026 spending per merchant category code (MCC) | 0.106 | 0.215 | 2.03× | < 250 ms | Pass |
| R15: Business insights: top 10 merchants by June 2026 GMV in each city | 4.237 | 138.346 | 32.65× | < 5,000 ms | Pass |
| R16: Disputes desk: disputes open for more than 7 days (SLA breached) | 0.322 | 8.117 | 25.21× | < 250 ms | Pass |
| R17: Merchant risk: refund rate per merchant (at least 30 payments) | 12.950 | 230.724 | 17.82× | < 5,000 ms | Pass |
| R18: Compliance: users without verified KYC who have successfully sent ₹10,000+ in total | 19.328 | 295.577 | 15.29× | < 5,000 ms | Pass |
| R19: Merchant report: last payment time and successful payment count of every verified Bengaluru merchant | 1.566 | 34.283 | 21.89× | < 5,000 ms | Pass |
| R20: Platform health: daily success rate in June 2026 | 2.940 | 68.911 | 23.44× | < 5,000 ms | Pass |
| R21: "Search businesses": merchants with "chai" in their name | 1.101 | 22.178 | 20.14× | < 250 ms | Pass |
| R22: Payment screen: user 15177's primary bank account and all their UPI IDs | 0.074 | 0.050 | 0.68× | < 5 ms | Pass |
| R23: Operations console: all transactions, newest first, page 8,001 (25 per page) | 21.569 | 22.133 | 1.03× | < 250 ms | Pass |
| R24: Customer support: find a payment by its UPI reference number | 0.032 | 0.182 | 5.69× | < 5 ms | Pass |
| R25: Bank health: average seconds from initiation to completion per payer bank (June 2026) | 16.037 | 178.768 | 11.15× | < 5,000 ms | Pass |
| W01: Pay: user 15177 starts a ₹250 payment to merchant 2 (PENDING until the bank confirms) | 0.809 | 1.304 | 1.61× | < 5 ms | Pass |
| W02: Bank callback: mark the oldest PENDING payment as successful | 0.290 | 0.615 | 2.12× | < 5 ms | Pass |
| W03: Scratch card: user 15177 scratches their oldest unscratched card | 0.199 | 0.133 | 0.67× | < 5 ms | Pass |
| W04: Nightly job (run at 00:00 on 4 Jul 2026): expire every reward whose time is up | 0.281 | 2.574 | 9.16× | < 1,000 ms | Pass |
| W05: Nightly job: bills past their due date and still unpaid become OVERDUE | 1.159 | 19.096 | 16.48× | < 1,000 ms | Pass |

**All 30 large-dataset averages met their listed target after adding a user-scoped covering index for R22.** R08 and R09 remain the slowest reads at about 1.63 s and 1.33 s because they aggregate/window over millions of qualifying transaction rows, but both remain below the 5 s analytics target. W05's bulk overdue-bill update averaged about 19 ms and remains below the 1 s batch target. The largest relative growth is shown in the table; bulk write cost tracks the increased number of rows updated.

R23 is a keyset-pagination design with a composite `(initiated_at DESC, txn_id DESC)` index. The standalone reproducible benchmark derives the page cursor with an `OFFSET 199999` CTE, so its measured 40.404 ms includes cursor discovery. A live client would send the last row's `(initiated_at, txn_id)` from the preceding page and avoid that offset scan. The deterministic transaction-ID tie-breaker also makes page boundaries stable when timestamps match.

## Integrity checks

- All nine CSVs loaded with their FK, unique, and CHECK constraints enabled. The loader completed and ran `ANALYZE`.
- Row counts matched the source files: 5,009,340 transactions, 800,000 users, 1,066,666 bank accounts and VPAs, 60,000 merchants, 798,991 rewards, 600,000 bills, 73,365 disputes, and 10 cities.
- The optimized workload completed for all 30 query IDs, three runs each. W01's test transaction (`txn_id=90000001`, `upi_ref=999900000001`) was absent after benchmarking; write tests use rollback.
- The seed verification suite passed all 36 checks: bidirectional equivalence checks for the six rewritten reads, successful execution of all 25 optimized reads, and rollback safety for all five writes. R13 is the documented correctness correction: NULL-sensitive `NOT IN` returns no rows, while `NOT EXISTS` returns 450 merchants with no transaction. The full equivalence suite was not completed on the large database: its original-versus-corrected R13 comparison was canceled after more than 3.5 minutes. All 30 optimized workload queries were benchmarked three times on the large database, and the W01 rollback sentinel and row counts were checked.
- Git status confirms `large_data/` is ignored; CSV data is not staged. The counts and write-rollback check are also saved in [`../benchmarks/results/large/integrity.txt`](../benchmarks/results/large/integrity.txt).

## Growth analysis

Selective point lookups and user-scoped queries remain below 1 ms at 20× scale after the R22 covering index (for example R01–R05, R10, R12, R14, R22, and R24). Their index seeks grow slowly with table size. Queries that aggregate broad date ranges or most matching rows grew with volume; see the measured Growth column for each query. Smaller queries show noisy ratios because their times are close to the timer and cache floor.

No query exceeded its Phase 5 target. The main scale costs are global transaction analytics (R08/R09), the all-row merchant anti-join (R13), and batch updates. For these, partitioning, pre-aggregated summaries, and carefully scheduled batch work become more important as volume grows.

## Storage

Sizes were measured after the final workload indexes were created. `Table bytes` and `index bytes` sum the nine base tables and their indexes; database size also includes PostgreSQL metadata and auxiliary files.

| Dataset | PostgreSQL database size | Table heap total | Index total |
|---|---:|---:|---:|
| Seed | 149 MB | 56 MB | 87 MB |
| Large | 2,836 MB | 1,102 MB | 1,779 MB |

The indexes occupy about 1.61× the large table heap. This read performance still adds disk and write-maintenance cost. If the row count reached 100× the original seed (about 25 million transactions, roughly five times this large dataset), a simple linear estimate is about 5.1 GiB of table heaps and 8.2 GiB of indexes, before WAL, backups, bloat, and growth in other files. This is an estimate, not a measurement.

## Partitioning design and pruning test

`sql/08_partitioning.sql` defines a monthly RANGE partitioned replacement for `transactions` on `initiated_at`, with a DEFAULT partition. The large data spans Jan 2025 through Jun 2026; monthly partitions fit date-bounded reporting and allow old months to be detached or archived. On the test copy, all 5,009,340 rows were routed into the partitioned table. A June 2026 aggregate plan pruned 18 of 19 partitions and scanned only `transactions_p2026_06`; the captured plan and its 19.062 ms execution time are in [`../benchmarks/results/large/partition_pruning.txt`](../benchmarks/results/large/partition_pruning.txt). The temporary partitioned copy was dropped after the test, so the reported large database size excludes it.

PostgreSQL requires a partitioned table's PRIMARY KEY and UNIQUE constraints to include the partition key. The example therefore uses `(txn_id, initiated_at)` and `(upi_ref, initiated_at)`. This does not enforce global uniqueness of `txn_id` or `upi_ref` alone; a production design needs a separate global key registry or revised referencing keys before replacing the current table. Queries without an `initiated_at` constraint, especially R08/R09, cannot prune by month and still visit many partitions.

## 100× architecture plan

- **Partitioning:** use monthly RANGE partitions on `initiated_at`, create the next month ahead of time, and detach/archive old partitions. Confirm the primary-key and foreign-key redesign before rollout.
- **Sharding:** hash by payer user/VPA is a reasonable write-routing key, but P2P sends, recipient history, merchant reporting, and risk queries cross payer shards. Keep a globally addressable transaction ID and use asynchronous cross-shard aggregation or a separate analytics store; avoid claiming payer sharding makes payee queries local.
- **Read replicas and caching:** send reporting/analytics reads (R06–R21 and R25, subject to freshness needs) to a replica or summary tables. Keep payment writes and immediate status checks on the primary. Cache merchant name search and stable reference data; don't cache payment status beyond the product's freshness tolerance.
- **Maintenance:** run `ANALYZE` after bulk loads and meaningful data changes; tune autovacuum for the frequently updated transactions/rewards/bills tables; monitor index bloat; refresh daily/monthly summary tables; archive old partitions and test restore procedures.

## Conclusion

The supplied 20× dataset loaded and all measured Phase 5 query targets passed with the current indexes. The measured results support the course-scale demonstration, not a production capacity guarantee. At larger volume, the main risks are the 1.8 GB index footprint, global analytics that cannot prune, and global uniqueness constraints under partitioning; address these before moving toward 100× scale.
