# CP4 Scalability Report

> **Status: measurement draft.** The large-data archive is not present in this checkout, so no large-workload timings, storage sizes, growth ratios, or partitioning plans are reported as measured. Fill the results sections after faculty's `large_data.zip` is available.

## 1. Measurement setup

The CP2 seed database contains 250,468 transactions. The assignment describes a later dataset with about 20 times the rows. These are input-size facts, not CP4 measurements.

When the archive is available:

1. Create a fresh database and load the nine CSVs from `large_data/` using this repository's `sql/01_schema.sql` and `sql/02_load_data.sql`.
2. Apply `sql/05_indexes.sql`, then run `ANALYZE`.
3. Record the PostgreSQL version, host, database size, table sizes, and index sizes.
4. Run only the optimized workload, three times per query, with the repository benchmark harness:

   ```sh
   ./benchmarks/run_benchmark.sh gpay_large large 3 sql/06_optimized_queries.sql
   ```

5. Save the harness output in `benchmarks/results/large/summary.csv` and its raw plans alongside it. Run `sql/08_partitioning.sql` on the same large database and retain the partition-pruning plans.

   ```sh
   psql -d gpay_large -v ON_ERROR_STOP=1 -f sql/08_partitioning.sql \
     > benchmarks/results/large/partitioning_plans.txt
   ```

## 2. Large-workload results

No large-data query results are recorded yet. Do not infer large-data values by multiplying the seed measurements.

| Query group | Query IDs | Measured average / target | Result |
|---|---|---:|---|
| Real-time / payment path | R01–R04, R10, R12, R22, R24, W01–W03 | Pending / under 5 ms | Pending run |
| Interactive merchant and operations | R05, R11, R13, R14, R16, R21, R23 | Pending / under 250 ms | Pending run |
| Reports, risk, and analytics | R06–R09, R15, R17–R20, R25 | Pending / under 5,000 ms | Pending run |
| Batch jobs | W04–W05 | Pending / under 1,000 ms | Pending run |

Populate the per-query table from `benchmarks/results/large/summary.csv` after running the workload. For each query calculate `large average / seed optimized average` and explain any target miss from its plan.

## 3. Partitioning design

The experiment in [`sql/08_partitioning.sql`](../sql/08_partitioning.sql) creates a monthly range-partitioned analytical copy of `gpay.transactions`, partitioned by `initiated_at` with month boundaries in `Asia/Kolkata` to match the reporting queries. Time-bounded reads such as daily history and month reports can exclude unrelated months through partition pruning. An all-history aggregate without an `initiated_at` predicate still has to visit every partition.

The partitioned table uses `(txn_id, initiated_at)` as its primary key. PostgreSQL requires a partitioned table's unique and primary-key constraints to include its partition key, so `txn_id` alone and `upi_ref` alone cannot remain globally unique on that table. The original `transactions` table remains authoritative in this experiment: `rewards` and `disputes` reference `txn_id` alone and would need a revised key or an unpartitioned transaction-key registry before a production migration. Compare the actual partitioned plans with the unpartitioned baseline before recommending deployment.

Record the `EXPLAIN (ANALYZE, BUFFERS)` output from both the month-bounded query and the all-history aggregate. The expected pruning behavior is a plan restricted to the matching month for the first query and all relevant partitions for the second; this expectation still needs confirmation from the actual database run.

## 4. Growth and storage analysis

Complete this section from the measured seed and large summaries. Group queries by observed growth (near constant, near row-count growth, or faster than row-count growth), and explain each group using its actual scan and join plans. Record total database size and the table/index size split for both databases.

| Measurement | Seed | Large | Evidence |
|---|---:|---:|---|
| PostgreSQL version and host | See CP2 report | Pending | `docs/03_baseline_timings.md` and run metadata |
| Database size | Pending | Pending | `pg_database_size()` |
| `transactions` table size | Pending | Pending | `pg_relation_size()` |
| `transactions` index size | Pending | Pending | `pg_indexes_size()` |

## 5. Design considerations at 100×

- **Partitioning:** retain time-range partitioning only if measured time-bounded queries prune partitions and the added key/FK complexity is acceptable. The current SQL is an experiment, not a production migration.
- **Sharding:** sharding by payer can localize a user's outgoing history, but P2P payments also touch a payee who may be on another shard. Recipient history, merchant settlement, and global fraud reports would need cross-shard reads or separately maintained reporting data. Choose a shard key only after measuring the actual workload and write path.
- **Read replicas and caching:** send stale-tolerant historical reports to replicas; payment writes and read-after-write screens must use the primary. Cache daily/weekly summaries only with clear invalidation after a reading or transaction change.
- **Maintenance:** measure write volume and dead tuples before changing autovacuum settings. Define retention and archival boundaries before detaching old partitions, and refresh any materialized summaries on a documented schedule.

## 6. Conclusion

Readiness at 20× cannot be determined until the large workload is run. The current partitioning DDL documents the primary-key and foreign-key tradeoffs, but the plan behavior, growth ratios, storage overhead, and target compliance remain unmeasured.
