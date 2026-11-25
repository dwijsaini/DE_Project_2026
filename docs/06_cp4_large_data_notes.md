# CP4 Large-Dataset Benchmark: Status & Readiness Notes

**Author:** Gyanshi  
**Date:** 2026-11-20 · **Team:** T0129 · **Database:** `gpay_cp3`  
**Status:** Blocked — `large_data.zip` not yet released by faculty as of 2026-11-20

---

## 1. Current Blocker: `large_data.zip` Not Released

As of **2026-11-20**, the faculty-provided large dataset (`large_data.zip`) has **not been released**. The CP4 large-dataset benchmark (`benchmarks/results/large/`) cannot be executed until this file becomes available.

All 30 rows in `benchmarks/results/large/summary.csv` are correctly marked as **PENDING** to reflect this:

```
query_id,type,avg_ms,median_ms,min_ms,max_ms,scan_nodes
R01,READ,PENDING,PENDING,PENDING,PENDING,(awaiting large_data.zip)
R02,READ,PENDING,PENDING,PENDING,PENDING,(awaiting large_data.zip)
...
```

**No timing numbers have been fabricated or estimated.** The existing `summary.csv` placeholder is accurate: no data has been processed.

---

## 2. What the Large Dataset Contains (Expected)

Based on the project brief (`README.md` / `CHECKPOINTS.md`), the large dataset is expected to represent approximately **20× the seed data volume**:

| Table | Seed dataset (~250K txns) | Expected large dataset |
|---|---:|---:|
| `transactions` | ~250,468 rows | ~5,000,000 rows |
| `users` | ~40,000 rows | ~800,000 rows |
| `vpas` | ~53,333 rows | ~1,066,000 rows |
| `rewards` | ~39,800 rows | ~796,000 rows |
| `bill_payments` | ~30,000 rows | ~600,000 rows |

---

## 3. Queries Projected to Be Problematic at 20× Scale

Based on the CP3 optimization report (`docs/04_optimization_report.md`) and the full scalability analysis (`docs/05_scalability_report.md` — authored by Dwij Saini, Group Lead), the following queries are projected to show the most significant performance degradation at 20× scale:

### R08 — Fraud: VPAs with 5+ distinct payers on same day
- **Why it will struggle:** Already shows an external sort spill (864 temp pages read/written) on the seed dataset. At 20×, the spill will grow proportionally (~17,000 temp pages), and GroupAggregate over 2M+ P2P rows will require substantially more time and disk I/O.
- **Mitigation in progress:** `docs/05_scalability_report.md` recommends a materialized partial pre-aggregate or summary table for the fraud detection pattern.

### R09 — P2P payment history with date range
- **Why it will struggle:** While the index `idx_transactions_success_payer_payee_initiated` eliminates the seed-dataset disk spill, at 20× scale the per-user result sets will grow. High-volume users may still trigger large index range scans.
- **Mitigation in progress:** Range partitioning on `initiated_at` (implemented in `sql/08_partitioning.sql`) limits each partition scan to a time-bounded slice.

### R23 — Operations console: paginated full-table scan with large OFFSET
- **Why it will struggle:** `OFFSET 200000 LIMIT 25` on 5M rows requires the planner to discard 200,000 rows before returning 25. The existing `idx_transactions_initiated_desc` index helps, but keyset (cursor) pagination is required at this scale.
- **Mitigation in progress:** `docs/05_scalability_report.md` documents cursor-based pagination as the recommended approach for the operations console at enterprise scale.

---

## 4. What Will Be Done When `large_data.zip` Arrives

Upon faculty release of `large_data.zip`, the following steps will be executed:

1. **Load the large dataset:**
   ```bash
   unzip large_data.zip -d large_data/
   psql -d gpay_cp3 -f sql/02_load_data.sql   # or equivalent large-data loader
   ```

2. **Apply indexes and partitioning:**
   ```bash
   psql -d gpay_cp3 -f sql/05_indexes.sql
   psql -d gpay_cp3 -f sql/08_partitioning.sql
   ```

3. **Run the large-dataset benchmark:**
   ```bash
   ./benchmarks/run_benchmark.sh gpay_cp3 large
   ```
   This will populate `benchmarks/results/large/` with actual timing data and raw `EXPLAIN (ANALYZE, BUFFERS)` plans, replacing the PENDING placeholders in `summary.csv`.

4. **Update this document** and `docs/05_scalability_report.md` with actual observed timings for R08, R09, and R23 to validate (or revise) the projections in Section 3 above.

---

## 5. Architecture Readiness

The full scalability architecture analysis — covering range partitioning on `transactions.initiated_at`, read-replica tiering, keyset pagination, in-memory caching layers, and the 100× enterprise horizon — is documented in:

> **[`docs/05_scalability_report.md`](05_scalability_report.md)** — authored by **Dwij Saini** (Group Lead, Team T0129)

That report also contains the rationale for `sql/08_partitioning.sql` (Rudra's implementation). This file (`docs/06_cp4_large_data_notes.md`) is a status tracker for the benchmark execution blocker; architectural decisions and projections belong in `docs/05_scalability_report.md`.

---

## 6. References

| File | Purpose |
|---|---|
| `benchmarks/results/large/summary.csv` | Benchmark summary (all PENDING until `large_data.zip` released) |
| `benchmarks/run_benchmark.sh` | Benchmark harness used for baseline and optimized runs |
| `docs/04_optimization_report.md` | CP3 optimization report (Gyanshi) — includes R08/R09/R23 plan analysis |
| `docs/05_scalability_report.md` | Full CP4 scalability and architecture analysis (Dwij Saini) |
| `sql/08_partitioning.sql` | Range partitioning implementation (Rudra) |
