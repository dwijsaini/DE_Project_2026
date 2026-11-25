# CP3 Optimization Report & Evidence Audit

**Auditor:** Gyanshi  
**Audit Date:** 20 November 2026  
**Target Repository:** `DE_Project_2026` (`T0129`)  
**Scope:** Independent evidence audit of Checkpoint 3 (CP3) optimization deliverables, cross-referencing all 30 queries across raw execution plans, benchmark summaries, and documented claims in [`docs/04_optimization_report.md`](04_optimization_report.md).

---

## 1. Executive Summary & Audit Methodology

This audit cross-examines the empirical benchmark evidence generated during the CP3 optimization phase against the claims documented in the project deliverables.

### Distinction of Verification Categories
To maintain scientific rigor, this audit strictly distinguishes between three independent verification criteria:
1. **Query Execution Success:** Whether the query executes against PostgreSQL without syntax or runtime error and successfully returns data. Verified across all 30 queries via automated workload test execution.
2. **Semantic Equivalence:** Whether the optimized query produces identical result sets to the baseline specification:
   - **Formally Verified (6 queries):** For the 6 rewritten queries (R01, R03, R13, R14, R20, R22), semantic equivalence is formally verified via bidirectional two-way `EXCEPT ALL` assertions in [`sql/07_verify_equivalence.sql`](../sql/07_verify_equivalence.sql).
   - **Not Independently Tested (24 queries):** For the remaining 24 queries (19 read queries, 5 write queries), the SQL text is **unmodified** from `queries/workload_30.sql`. While execution success is confirmed, **no independent equivalence test (e.g., `EXCEPT ALL` assertions or result set comparisons) was performed**; equivalence is assumed on the basis of unchanged SQL syntax and relational engine invariants.
3. **Performance Outcome:** Whether average measured execution time improved, remained flat, or regressed under the index set. Measured by the arithmetic mean of 3 consecutive runs under warm-cache conditions.

### Source Evidence Audited
1. **Baseline Summary:** [`benchmarks/results/baseline/summary.csv`](../benchmarks/results/baseline/summary.csv) (30 queries, 3 runs each).
2. **Optimized Summary:** [`benchmarks/results/optimized/summary.csv`](../benchmarks/results/optimized/summary.csv) (30 queries, 3 runs each).
3. **Raw Plan Outputs:** 60 execution plan files (`benchmarks/results/baseline/*.txt` and `benchmarks/results/optimized/*.txt`), auditing node types, worker parallelism, buffer counters (`shared hit`, `shared read`, `dirtied`), and temporary memory/disk spills.
4. **Optimized SQL & Indexes:** [`sql/06_optimized_queries.sql`](../sql/06_optimized_queries.sql) and [`sql/05_indexes.sql`](../sql/05_indexes.sql) (defining 15 workload B-tree indexes).
5. **Workload Verification Suite:** Automated execution via [`benchmarks/verify_workload.sh`](../benchmarks/verify_workload.sh) and [`sql/07_verify_equivalence.sql`](../sql/07_verify_equivalence.sql).

### Benchmark Environment Verification
- **PostgreSQL Version:** `PostgreSQL 18.6 (Postgres.app) on aarch64-apple-darwin23.6.0, compiled by Apple clang version 15.0.0 (clang-1500.3.9.4), 64-bit`
- **Host Hardware:** Apple MacBook Pro (Apple M4, macOS Darwin arm64)
- **Active Database:** `gpay_cp3` (seed dataset: 250,468 transactions, 50,000 users, 53,333 VPAs, 3,000 merchants, 39,799 rewards, 30,000 bills)

---

## 2. Comprehensive 30-Query Audit Matrix

Every timing below represents the arithmetic mean of 3 consecutive runs measured under identical system configurations, extracted directly from `summary.csv` and verified against raw plan files.

| Query ID | SQL Status | Baseline Avg (ms) | Optimized Avg (ms) | Absolute $\Delta$ (ms) | Speedup Factor | Improvement (%) | Baseline Scan Nodes | Optimized Scan Nodes | Temp Disk Spill (Baseline $\rightarrow$ Opt) | Equivalence Verification | Performance Outcome |
|:---|:---|---:|---:|---:|---:|---:|:---|:---|:---:|:---:|:---:|
| **R01** | Rewritten (`UNION`) | 24.783 | 0.264 | -24.519 | 93.88× | **+98.93%** | Parallel Seq Scan (`transactions`) + Seq Scan (`vpas`) | Index Only Scan (`idx_vpas_user_id_vpa`) + Bitmap Heap/Index Scan (`transactions`) | None $\rightarrow$ None | **Verified (Two-Way EXCEPT ALL)** | **Improved** |
| **R02** | Unchanged | 0.291 | 0.073 | -0.218 | 3.99× | **+74.91%** | Index Scan (`vpas_pkey`, `users_pkey`) | Index Scan (`vpas_pkey`, `users_pkey`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R03** | Rewritten (Range) | 11.761 | 0.071 | -11.690 | 165.65× | **+99.40%** | Parallel Seq Scan (`transactions`) + Seq Scan (`vpas`) | Index Only Scan (`idx_vpas_user_id_vpa`) + Index Scan (`idx_transactions_payer_vpa_initiated_desc`) | None $\rightarrow$ None | **Verified (Two-Way EXCEPT ALL)** | **Improved** |
| **R04** | Unchanged | 7.432 | 0.060 | -7.372 | 123.87× | **+99.19%** | Parallel Seq Scan (`transactions`) | Index Scan (`idx_transactions_pending_initiated`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R05** | Unchanged | 6.667 | 0.132 | -6.535 | 50.51× | **+98.02%** | Parallel Seq Scan (`transactions`) | Index Scan (`idx_transactions_merchant_initiated`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R06** | Unchanged | 6.969 | 0.982 | -5.987 | 7.10× | **+85.91%** | Parallel Seq Scan (`transactions`) + Index Scan (`merchants_pkey`) | Index Scan (`idx_transactions_initiated_desc`) + Seq Scan (`merchants`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R07** | Unchanged | 10.054 | 2.352 | -7.702 | 4.27× | **+76.61%** | Parallel Seq Scan (`transactions`) + Index Scan (`vpas_pkey`, `bank_accounts_..._key`) | Index Scan (`idx_transactions_initiated_desc`, `vpas_pkey`, `bank_accounts_..._key`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R08** | Unchanged | 119.070 | 259.517 | +140.447 | 0.46× | **-117.95%** | Seq Scan (`transactions`) | Seq Scan (`transactions`) | **6.9 MB $\rightarrow$ 6.9 MB (PERSISTS)** | Not Independently Tested (Identical SQL Text) | **Regressed** |
| **R09** | Unchanged | 262.420 | 236.894 | -25.526 | 1.11× | **+9.73%** | Seq Scan (`transactions`) | Index Scan (`idx_transactions_success_payer_payee_initiated`) | **17.8 MB $\rightarrow$ 0 kB (ELIMINATED)** | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R10** | Unchanged | 2.452 | 0.050 | -2.402 | 49.04× | **+97.96%** | Seq Scan (`rewards`) | Index Scan (`idx_rewards_unscratched_user_expiry`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R11** | Unchanged | 1.680 | 0.067 | -1.613 | 25.07× | **+96.01%** | Seq Scan (`rewards`) | Index Scan (`idx_rewards_unscratched_expiry`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R12** | Unchanged | 1.761 | 0.050 | -1.711 | 35.22× | **+97.16%** | Seq Scan (`bill_payments`) | Index Scan (`idx_bills_due_user_date`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R13** | Rewritten (`NOT EXISTS`) | 21.979 | 6.470 | -15.509 | 3.40× | **+70.56%** | Seq Scan (`merchants`, `transactions`) | Seq Scan (`merchants`) + Index Only Scan (`idx_transactions_merchant_initiated`) | None $\rightarrow$ None | **Verified (Two-Way EXCEPT ALL vs intended; fixes 0 $\rightarrow$ 450 rows)** | **Improved** |
| **R14** | Rewritten (Range) | 17.336 | 0.210 | -17.126 | 82.55× | **+98.79%** | Parallel Seq Scan (`transactions`) + Seq Scan (`vpas`) + Index Scan (`merchants_pkey`) | Index Only Scan (`idx_vpas_user_id_vpa`) + Bitmap Heap/Index Scan (`transactions`) + Index Scan (`merchants_pkey`) | None $\rightarrow$ None | **Verified (Two-Way EXCEPT ALL)** | **Improved** |
| **R15** | Unchanged | 9.235 | 8.227 | -1.008 | 1.12× | **+10.91%** | Parallel Seq Scan (`transactions`) + Seq Scan (`merchants`) | Index Scan (`idx_transactions_initiated_desc`) + Seq Scan (`merchants`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R16** | Unchanged | 0.805 | 0.663 | -0.142 | 1.21× | **+17.64%** | Seq Scan (`disputes`) + Index Scan (`transactions_pkey`) | Seq Scan (`disputes`) + Index Scan (`transactions_pkey`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R17** | Unchanged | 11.455 | 36.603 | +25.148 | 0.31× | **-219.54%** | Parallel Seq Scan (`transactions`) | Parallel Seq Scan (`transactions`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Regressed** |
| **R18** | Unchanged | 23.201 | 38.489 | +15.288 | 0.60× | **-65.89%** | Parallel Seq Scan (`transactions`) + Seq Scan (`vpas`, `users`) | Parallel Index Only Scan (`idx_vpas_user_id_vpa`) + Seq Scan (`users`) + Index Scan (`idx_transactions_payer_vpa_initiated_desc`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Regressed** |
| **R19** | Unchanged | 4185.057 | 2.796 | -4182.261 | 1496.80× | **+99.93%** | Seq Scan (`merchants`, `transactions`) | Seq Scan (`merchants`) + 2× Index Only Scan (`idx_transactions_merchant_initiated`, `idx_transactions_success_merchant`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved (Core Win)** |
| **R20** | Rewritten (Range) | 9.869 | 5.721 | -4.148 | 1.73× | **+42.03%** | Parallel Seq Scan (`transactions`) | Index Scan (`idx_transactions_initiated_desc`) | None $\rightarrow$ None | **Verified (Two-Way EXCEPT ALL)** | **Improved** |
| **R21** | Unchanged | 1.009 | 2.207 | +1.198 | 0.46× | **-118.73%** | Seq Scan (`merchants`) | Seq Scan (`merchants`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Regressed** |
| **R22** | Rewritten (Join FK) | 3.497 | 1.215 | -2.282 | 2.88× | **+65.26%** | Seq Scan (`vpas`) + Index Scan (`bank_accounts_account_id_user_id_key`) | Index Scan (`bank_accounts_account_id_user_id_key`, `idx_vpas_user_id_vpa`) | None $\rightarrow$ None | **Verified (Two-Way EXCEPT ALL)** | **Improved** |
| **R23** | Unchanged | 59.579 | 40.435 | -19.144 | 1.47× | **+32.13%** | Seq Scan (`transactions`) | Index Scan (`idx_transactions_initiated_desc`) | **14.2 MB $\rightarrow$ 0 kB (ELIMINATED)** | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R24** | Unchanged | 0.616 | 0.074 | -0.542 | 8.32× | **+87.99%** | Index Scan (`transactions_upi_ref_key`) | Index Scan (`transactions_upi_ref_key`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **R25** | Unchanged | 20.972 | 30.794 | +9.822 | 0.68× | **-46.83%** | Parallel Seq Scan (`transactions`) + Seq Scan (`vpas`, `bank_accounts`) | Index Scan (`idx_transactions_initiated_desc`) + Seq Scan (`bank_accounts`, `vpas`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Regressed** |
| **W01** | Unchanged | 2.014 | 1.376 | -0.638 | 1.46× | **+31.68%** | Insert (no scan) | Insert (no scan) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **W02** | Unchanged | 20.489 | 0.635 | -19.854 | 32.27× | **+96.90%** | Index Scan (`transactions_pkey`) | Index Only Scan (`idx_transactions_pending_txn_id`) + Index Scan (`transactions_pkey`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **W03** | Unchanged | 2.696 | 0.368 | -2.328 | 7.33× | **+86.35%** | Seq Scan (`rewards`) + Index Scan (`rewards_pkey`) | Index Only Scan (`idx_rewards_unscratched_user_reward`) + Index Scan (`rewards_pkey`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **W04** | Unchanged | 2.622 | 0.618 | -2.004 | 4.24× | **+76.43%** | Seq Scan (`rewards`) | Index Scan (`idx_rewards_unscratched_expiry`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |
| **W05** | Unchanged | 3.718 | 1.989 | -1.729 | 1.87× | **+46.50%** | Seq Scan (`bill_payments`) | Bitmap Heap Scan (`bill_payments`) + Bitmap Index Scan (`idx_bills_due_date`) | None $\rightarrow$ None | Not Independently Tested (Identical SQL Text) | **Improved** |

---

## 3. Independent Verification of Headline Claims

### Claim 1: Total Workload Execution Time Reduced by 86.00%
- **Empirical Sums:**
  $$\sum T_{\text{base}} = 4,851.489\text{ ms}, \quad \sum T_{\text{opt}} = 679.402\text{ ms}$$
  $$\text{Workload Improvement} = \frac{4,851.489 - 679.402}{4,851.489} \times 100 = \frac{4,172.087}{4,851.489} \times 100 = 85.9960\% \approx \mathbf{86.00\%}$$
  $$\text{Overall Workload Speedup} = \frac{4,851.489}{679.402} = \mathbf{7.141\times}$$
- **Audit Verification:** **CONFIRMED & MATHEMATICALLY EXACT.**

### Claim 2: Core Bottleneck R19 Accelerated by 1,496.8× (99.93% Reduction)
- **Empirical Calculation:**
  $$\Delta = 2.796\text{ ms} - 4,185.057\text{ ms} = -4,182.261\text{ ms}$$
  $$\text{Improvement} = \frac{4,182.261}{4,185.057} \times 100 = \mathbf{99.933\%}$$
  $$\text{Speedup} = \frac{4,185.057}{2.796} = \mathbf{1,496.80\times}$$
- **Audit Verification:** **CONFIRMED.** Correlated subqueries in `queries/workload_30.sql` performed repeated sequential table scans over 250,468 transaction rows per merchant. Dedicated partial indexes (`idx_transactions_merchant_initiated` and `idx_transactions_success_merchant`) converted both subplans into pure Index Only Scans with 0 heap fetches, reducing average execution time from 4,185.057 ms to 2.796 ms.

### Claim 3: Elimination of Temporary Disk Spills in R09 and R23
- **Evidence from Raw Plan Files:**
  - **R09 Baseline:** Raw plans `benchmarks/results/baseline/R09.txt` show `Sort Method: external merge Disk: 17776kB` with `temp read=2222 written=2228` across all three runs (259.392 ms, 259.693 ms, 268.175 ms).
  - **R09 Optimized:** Raw plans `benchmarks/results/optimized/R09.txt` show `Sort Method: quicksort Memory: 70kB` (for outer ordering) with `temp read=0 written=0` across all three runs (227.789 ms, 257.822 ms, 225.071 ms). The index `idx_transactions_success_payer_payee_initiated` directly feeds pre-sorted rows into `WindowAgg`. **Disk spill eliminated.**
  - **R23 Baseline:** Raw plans `benchmarks/results/baseline/R23.txt` show `Sort Method: external merge Disk: 14224kB` with `temp read=1550 written=1783` across all three runs (58.487 ms, 58.299 ms, 61.950 ms).
  - **R23 Optimized:** Raw plans `benchmarks/results/optimized/R23.txt` show no sort node (`Sort Method: (none)`), with rows fetched directly via `Index Scan using idx_transactions_initiated_desc` and `temp read=0 written=0` across all three runs (41.184 ms, 40.373 ms, 39.748 ms). **Disk spill eliminated.**
- **Audit Verification:** **CONFIRMED.** A combined **32.0 MB** (32,000 kB) of temporary disk spills was eliminated.

### Claim 4: Persistent Temporary Disk Spill in R08
- **Evidence from Raw Plan Files:**
  - **R08 Baseline:** Plans show `Sort Method: external merge Disk: 6912kB` with `temp read=864 written=866` in all three runs (119.904 ms, 118.702 ms, 118.604 ms).
  - **R08 Optimized:** Plans show `Sort Method: external merge Disk: 6912kB` with `temp read=864 written=866` in all three runs (265.616 ms, 256.585 ms, 256.349 ms).
- **Audit Verification:** **CONFIRMED PERSISTENT.** R08 continues to spill **6,912 kB (6.9 MB)** of intermediate sort data to disk in both baseline and optimized execution plans. As documented in Section 3 of `docs/04_optimization_report.md`, an attempted rewrite with pre-aggregation increased disk spill to 7,544 kB, leading the team to preserve the original query.

### Claim 5: Correctness Fix on Inactive Merchants (R13)
- **Relational Proof:**
  - Total registered merchants: **3,000**.
  - Distinct merchants appearing in `transactions`: **2,550**.
  - Expected inactive merchants: $3,000 - 2,550 = \mathbf{450}$.
  - Baseline `NOT IN` query: returns **0 rows** because 110,581 P2P records contain `merchant_id IS NULL`. Under three-valued logic, `NOT IN (..., NULL)` evaluates to `UNKNOWN` for all rows.
  - Optimized `NOT EXISTS` query: returns **450 rows**.
  - Bidirectional equivalence check against intended anti-join (`NOT IN (... WHERE merchant_id IS NOT NULL)`): **0 row differences in both directions** via `sql/07_verify_equivalence.sql`.
- **Audit Verification:** **CONFIRMED.**

---

## 4. Query Regression Audit: Facts vs Hypotheses

Five queries exhibited higher average execution times in the optimized benchmark. This audit separates **direct plan evidence** from **unverified hypotheses**:

### R08 (+140.45 ms: 119.070 ms $\rightarrow$ 259.517 ms)
- **Direct Plan Evidence:** Both baseline and optimized execute identical query plans: a single-threaded `Seq Scan on transactions` filtering 102,742 rows (`txn_type = 'P2P' AND status = 'SUCCESS'`), followed by an external merge sort with `Sort Method: external merge Disk: 6912kB` (`temp read=864 written=866`) feeding `GroupAggregate`.
- **Buffer & Disk Evidence:** Baseline buffer accesses were `shared hit=4223 read=274` (run 1), `shared hit=4317 read=180` (run 2), and `shared hit=4411 read=86` (run 3). In optimized runs, all buffer touches were cache hits: `shared hit=4497 read=0` across all three runs.
- **Audit Finding:** The plan structure did not regress, and the 6.9 MB temporary disk spill persisted identically. However, measured execution time increased from 119.070 ms to 259.517 ms (+140.447 ms). Because buffer hits were actually higher in the optimized runs, plan artifacts provide no empirical evidence explaining the timing increase. Speculative attributions in project reports to "cache-warm run-order variance" or temporary disk write contention are not instrumented and are therefore classified as **NOT VERIFIED**.

### R17 (+25.15 ms: 11.455 ms $\rightarrow$ 36.603 ms)
- **Direct Plan Evidence:** Both plans are structurally identical: `Parallel Seq Scan on transactions` with 2 planned and launched background workers (scanning 46,629 rows/loop), followed by `Gather`, `Finalize HashAggregate`, and `Sort Method: top-N heapsort Memory: 26kB`. Buffer access was identical: `shared hit=4491 read=0` across all runs in both phases.
- **Run Distribution:** Baseline execution times were 11.216 ms, 11.718 ms, and 11.430 ms (avg 11.455 ms). Optimized execution times were 23.471 ms, 21.475 ms, and 64.862 ms (avg 36.603 ms, median 23.471 ms).
- **Audit Finding:** The plan structure did not de-optimize. All three optimized runs executed slower than baseline (~21–23 ms for runs 1 and 2, with run 3 spiking to 64.862 ms). Documentation attributing this regression to "parallel worker scheduling jitter on macOS" or "OS scheduler latency" represents an unverified hypothesis lacking empirical thread trace data in the benchmark logs; it is classified as **NOT VERIFIED** as an established fact.

### R18 (+15.29 ms: 23.201 ms $\rightarrow$ 38.489 ms)
- **Direct Plan Evidence:**
  - *Baseline plan:* Parallel execution with 2 workers using `Parallel Seq Scan on transactions` (77,636 rows/loop), `Seq Scan on vpas`, `Seq Scan on users`, and a bulk `Hash Join`. Buffer usage: `shared hit=7052 read=487` (run 1), `shared hit=7539 read=0` (runs 2 and 3). Avg: 23.201 ms.
  - *Optimized plan:* PostgreSQL abandoned the bulk hash join and selected a `Nested Loop` with `Merge Join` (`Parallel Index Only Scan using idx_vpas_user_id_vpa on vpas` + `Sort` over `Seq Scan on users`) driving an inner `Index Scan using idx_transactions_payer_vpa_initiated_desc on transactions` executed across **5,237 loops**. Buffer usage: **`shared hit=42285`** in all runs. Avg: 38.489 ms.
- **Audit Finding:** **Confirmed plan-shape regression.** The introduction of `idx_vpas_user_id_vpa` caused the optimizer cost model to favor nested-loop index seeks over a bulk hash join. Probing the index 5,237 times incurred 42,285 shared buffer hits (a 5.6× increase in page touches over baseline's 7,536), requiring more CPU execution time (+15.288 ms).

### R21 (+1.20 ms: 1.009 ms $\rightarrow$ 2.207 ms)
- **Direct Plan Evidence:** Both baseline and optimized execute an identical single-threaded `Seq Scan on merchants` filtering `merchant_name ~~* '%chai%'`, scanning 35 disk pages (`shared hit=38`), followed by `Sort Method: top-N heapsort Memory: 30kB`.
- **Run Distribution:** Baseline execution times were 1.027 ms, 1.001 ms, and 0.999 ms (avg 1.009 ms). Optimized execution times were 2.260 ms, 2.182 ms, and 2.178 ms (avg 2.207 ms).
- **Audit Finding:** Plan nodes and buffer counts are identical. While the absolute delta is small (+1.198 ms), assertions in deliverables attributing this delta to "OS scheduler preemption", "CPU cache state between runs", or "TLB effects" are unproven conjectures without hardware profiling evidence, and are classified as **NOT VERIFIED**.

### R25 (+9.82 ms: 20.972 ms $\rightarrow$ 30.794 ms)
- **Direct Plan Evidence:**
  - *Baseline plan:* Parallel execution with 2 workers using `Gather Merge`, `Parallel Seq Scan on transactions`, `Seq Scan on vpas`, and `Seq Scan on bank_accounts`. Buffer usage: `shared hit=7542 read=541` (run 1), `shared hit=8083` (runs 2 and 3). Avg: 20.972 ms.
  - *Optimized plan:* Single-threaded execution (0 parallel workers) using `Index Scan using idx_transactions_initiated_desc on transactions`, `Seq Scan on bank_accounts`, and `Seq Scan on vpas`, followed by serial `HashAggregate`. Buffer usage: **`shared hit=1535`** across all runs. Avg: 30.794 ms.
- **Audit Finding:** **Confirmed optimizer parallelism tradeoff.** The index `idx_transactions_initiated_desc` reduced total buffer page touches by **81.0%** (from 8,083 down to 1,535). However, because the estimated planner cost dropped below the parallel execution threshold, PostgreSQL selected a serial plan rather than spawning 2 background parallel workers. Performing hash joins and aggregation on a single thread took ~30.8 ms wall-clock time vs ~21.0 ms under parallel workers (+9.822 ms).

---

## 5. Write Query & Index Overhead Audit

Adding 15 B-tree indexes across tables introduces potential write-amplification risks during DML. The 5 write queries were audited from raw plan outputs:

| Write Query | Operation | Baseline Avg (ms) | Optimized Avg (ms) | Speedup Factor | Index Paths & Plan Observations |
|---|---|---:|---:|---:|---|
| **W01** | `INSERT INTO transactions` | 2.014 | 1.376 | 1.46× | Single-row insert into `transactions` (evaluating table constraints and updating applicable indexes). Buffer touches increased from 82 to 230 shared hits due to index maintenance; execution time maintained sub-1.5 ms latency. |
| **W02** | `UPDATE transactions (oldest PENDING)` | 20.489 | 0.635 | 32.27× | Baseline performed an `Index Scan using transactions_pkey on transactions` scanning 249,875 index entries to filter for pending status (`shared hit=5120`). Optimized plan uses `Index Only Scan using idx_transactions_pending_txn_id` (`shared hit=3`) for instant target row identification, followed by PK lookup. |
| **W03** | `UPDATE rewards (oldest UNSCRATCHED)` | 2.696 | 0.368 | 7.33× | Baseline performed `Seq Scan on rewards` (`shared hit=941`) to find target row. Optimized uses partial index `idx_rewards_unscratched_user_reward` (`shared hit=3`), followed by PK lookup. |
| **W04** | `UPDATE rewards (expire UNSCRATCHED)` | 2.622 | 0.618 | 4.24× | Baseline performed `Seq Scan on rewards` (`shared hit=941`). Optimized uses `Index Scan using idx_rewards_unscratched_expiry` (`shared hit=6` index read) to filter expiring unscratched cards directly. |
| **W05** | `UPDATE bill_payments (mark DUE OVERDUE)` | 3.718 | 1.989 | 1.87× | Baseline performed `Seq Scan on bill_payments` (`shared hit=572`). Optimized uses `Bitmap Heap Scan` + `Bitmap Index Scan using idx_bills_due_date` (`shared hit=2` index read). |

**Total Write Workload:** Decreased from **31.539 ms** to **4.986 ms** (**84.19% reduction**, **6.33× speedup**).  
**Audit Finding:** Workload write amplification did not degrade performance. Because W02–W05 perform filtering subqueries to identify target rows prior to update, partial B-tree indexing accelerated the read-before-write phase far more than index maintenance added to write overhead.

---

## 6. Audit of CP4 Large Dataset Claims (Unverifiable Boundaries)

| Claim / Deliverable | Audited Deliverable | Status | Audit Finding |
|---|---|:---:|---|
| CP4 20× Large Data Benchmark | `benchmarks/results/large/summary.csv` | **NOT VERIFIED** | **BLOCKED:** Faculty has not released `large_data.zip` as of 20 November 2026. All 30 query rows are correctly maintained as `PENDING`. No empirical large data timings exist. |
| Partitioning DDL | `sql/08_partitioning.sql` | **NOT VERIFIED** | Uncommitted/untracked file in working tree; not evaluated against empirical benchmark runs. |
| Scalability Report | `docs/05_scalability_report.md` | **NOT VERIFIED** | Uncommitted/untracked document in working tree; contains theoretical extrapolations rather than verified empirical measurements. |

---

## 7. Final Audit Verification Sign-Off

- [x] All 30 baseline execution times match `benchmarks/results/baseline/summary.csv`.
- [x] All 30 optimized execution times match `benchmarks/results/optimized/summary.csv`.
- [x] Workload execution time reduction of 86.00% (85.9960%) and 7.14× speedup independently confirmed.
- [x] Elimination of 32.0 MB temporary disk spills for R09 and R23 confirmed in raw plan files.
- [x] Persistent 6.9 MB (6,912 kB) temporary disk spill for R08 confirmed in raw plan files for both baseline and optimized runs.
- [x] Independent two-way `EXCEPT ALL` semantic equivalence confirmed for all 6 rewritten queries (R01, R03, R13, R14, R20, R22) via `sql/07_verify_equivalence.sql`.
- [x] Confirmed that the remaining 24 queries retain identical SQL text from `queries/workload_30.sql` (no independent `EXCEPT ALL` assertions were executed for these 24 queries).
- [x] Execution integrity of all 30 queries verified passing via `./benchmarks/verify_workload.sh gpay_cp3`.
- [x] Database state preservation (0 persistent table mutations) confirmed.
- [x] Unverified hypotheses regarding OS scheduling, worker jitter, and cache variance identified and classified as **NOT VERIFIED**.
