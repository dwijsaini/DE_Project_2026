# CP3 optimization report — in progress

**Status:** The CP2 baseline has now been measured for all 30 queries. This report contains the measured baseline averages and plan observations. The optimized workload has not yet been benchmarked, so the after-times, improvements, result checks, index storage, and write overhead remain pending. The authoritative three-run averages and raw plans are in [`benchmarks/results/baseline/`](../benchmarks/results/baseline/); the run-by-run table and baseline analysis are in [`03_baseline_timings.md`](03_baseline_timings.md).

The index and rewrite assignments are still in progress. Do not fill the remaining columns with estimates. Keep `queries/workload_30.sql` unchanged. For performance-only rewrites, prove equal results; document a correction to a wrong original result separately.

| Query | Before (ms) | Problem found in baseline plan | Optimization applied | After (ms) | Improvement | Same result? |
|---|---:|---|---|---:|---:|:---:|
| R01 | 24.783 | Parallel scan of all transactions; two VPA scans for the OR predicate; sort by time. | | | | |
| R02 | 0.291 | Uses VPA and user primary-key indexes; already fast. | | | | |
| R03 | 11.761 | Parallel transaction scan plus VPA scan; `DATE(initiated_at)` filter. | | | | |
| R04 | 7.432 | Parallel transaction scan for pending rows, then sort by initiation time. | | | | |
| R05 | 6.667 | Parallel transaction scan for merchant, status, and date range. | | | | |
| R06 | 6.969 | Parallel transaction scan, merchant join, aggregation, and settlement sort. | | | | |
| R07 | 10.054 | Parallel transaction scan for failures, then VPA/account joins and aggregation sorts. | | | | |
| R08 | 119.070 | Transaction scan and grouping sort spill about 6.9 MB to disk. | | | | |
| R09 | 262.420 | Transaction scan and window sort spill about 17.8 MB to disk; another sort follows. | | | | |
| R10 | 2.452 | Scans all rewards for one user's status/expiry filter, then sorts. | | | | |
| R11 | 1.680 | Scans rewards for status/expiry filter, then sorts. | | | | |
| R12 | 1.761 | Scans all bills for one user's status/date filter, then sorts. | | | | |
| R13 | 21.979 | Scans merchants and transactions. `NOT IN` sees NULL `merchant_id` values from P2P rows, so the original query returns no merchants; investigate as a correctness bug. | | | | |
| R14 | 17.336 | Scans transactions and VPAs; applies year extraction to transaction timestamps before grouping. | | | | |
| R15 | 9.235 | Parallel transaction scan, merchant join, aggregation, and ranking/sorts by city. | | | | |
| R16 | 0.805 | Scans the small disputes table and uses transaction primary-key lookups; already fast. | | | | |
| R17 | 11.455 | Parallel scan of P2M transactions followed by merchant aggregation. | | | | |
| R18 | 23.201 | Parallel transaction scan plus VPA/user scans and joins, grouping, and sort. | | | | |
| R19 | 4,185.057 | Two correlated subqueries each rescan transactions for each of 239 merchants. | | | | |
| R20 | 9.869 | Parallel transaction scan; casts timestamps to dates for filter/grouping, then sorts. | | | | |
| R21 | 1.009 | Scans 3,000 merchants for substring search; small table and low baseline time. | | | | |
| R22 | 3.497 | Scans all 53,333 VPAs for one user's account view; bank-account lookup uses an index. | | | | |
| R23 | 59.579 | Scans and sorts all transactions; sort spills about 14.2 MB, then OFFSET discards 200,000 rows. | | | | |
| R24 | 0.616 | Uses the unique UPI-reference index; already fast. | | | | |
| R25 | 20.972 | Scans transactions and VPAs, joins bank accounts, then groups by bank. | | | | |
| W01 | 2.014 | Insert-only plan has no scan node; write overhead still needs comparison after indexing. | | | | |
| W02 | 20.489 | Finds the oldest pending row by filtering nearly the full transaction table before a primary-key update. | | | | |
| W03 | 2.696 | Scans rewards to find the oldest qualifying card, then updates by primary key. | | | | |
| W04 | 2.622 | Scans rewards for expired, unscratched rows. | | | | |
| W05 | 3.718 | Scans bills for due unpaid rows past the cutoff. | | | | |
| **Total** | **4,851.489** | Sum of the per-query baseline averages; dominated by R19. | | | | |

## Remaining CP3 evidence

- Benchmark `sql/06_optimized_queries.sql` with the required repeated runs; save `benchmarks/results/optimized/summary.csv` and raw plans.
- Complete optimized query and index columns above using only benchmark evidence.
- Prove output equivalence for every performance rewrite using row counts and a checksum or two-way `EXCEPT`.
- Explain and correct R13's NULL-sensitive `NOT IN` behavior as a correctness fix, separately from performance-only rewrites.
- Include before/after plans for the five largest measured improvements.
- Measure write-query overhead and the size of each added index relative to its table.
- Explain queries that do not improve or must read much of a table.

Improvement percentage is `(before - after) / before * 100`. Use the same database and laptop as the baseline run. Do not change the data or PostgreSQL settings to force a plan.
