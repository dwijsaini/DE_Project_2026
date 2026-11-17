# CP2 baseline timings

**Run date:** 17 November 2026 · **Database:** `gpay_cp1` · **PostgreSQL:** 18.7
**Method:** repository benchmark script, `EXPLAIN (ANALYZE, BUFFERS)`, three runs per query. Write queries ran in transactions that were rolled back. Times below are milliseconds; averages are the arithmetic mean of the three raw `Execution Time` readings.

Raw plans and the generated average/median/min/max summary are in [`benchmarks/results/baseline/`](../benchmarks/results/baseline/). The original workload file was not modified.

| Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01 Transaction history | READ | 44.852 | 14.958 | 14.540 | 24.783 |
| R02 VPA lookup | READ | 0.818 | 0.027 | 0.028 | 0.291 |
| R03 Daily UPI limit check | READ | 11.690 | 11.731 | 11.861 | 11.761 |
| R04 Stale pending payments | READ | 7.521 | 7.266 | 7.509 | 7.432 |
| R05 Hourly merchant collections | READ | 6.691 | 6.561 | 6.749 | 6.667 |
| R06 Merchant settlement totals | READ | 7.704 | 6.572 | 6.632 | 6.969 |
| R07 Failure codes by payer bank | READ | 16.453 | 6.907 | 6.802 | 10.054 |
| R08 P2P recipients with 5+ payers | READ | 119.904 | 118.702 | 118.604 | 119.070 |
| R09 Repeated payments within 10 minutes | READ | 259.392 | 259.693 | 268.175 | 262.420 |
| R10 User's active unscratched rewards | READ | 4.474 | 1.530 | 1.352 | 2.452 |
| R11 Rewards expiring soon | READ | 1.667 | 1.779 | 1.593 | 1.680 |
| R12 User's upcoming bills | READ | 3.125 | 1.092 | 1.067 | 1.761 |
| R13 Merchants with no payments | READ | 22.091 | 22.303 | 21.542 | 21.979 |
| R14 User spending by merchant category | READ | 16.997 | 17.683 | 17.328 | 17.336 |
| R15 Top merchants by city | READ | 8.980 | 9.363 | 9.361 | 9.235 |
| R16 Open disputes past SLA | READ | 1.866 | 0.275 | 0.273 | 0.805 |
| R17 Merchant refund rate | READ | 11.216 | 11.718 | 11.430 | 11.455 |
| R18 Non-verified users with high spend | READ | 24.219 | 22.679 | 22.704 | 23.201 |
| R19 Verified Bengaluru merchant report | READ | 4,164.094 | 4,170.588 | 4,220.488 | 4,185.057 |
| R20 Daily success rate | READ | 10.073 | 9.744 | 9.789 | 9.869 |
| R21 Merchant name search | READ | 1.027 | 1.001 | 0.999 | 1.009 |
| R22 User's primary account and VPAs | READ | 4.574 | 2.980 | 2.937 | 3.497 |
| R23 Transaction page 8,001 | READ | 58.487 | 58.299 | 61.950 | 59.579 |
| R24 UPI reference lookup | READ | 1.783 | 0.033 | 0.033 | 0.616 |
| R25 Average completion time by payer bank | READ | 22.671 | 20.153 | 20.091 | 20.972 |
| W01 Create pending payment | WRITE | 5.013 | 0.524 | 0.506 | 2.014 |
| W02 Complete oldest pending payment | WRITE | 24.094 | 18.568 | 18.806 | 20.489 |
| W03 Credit oldest unscratched reward | WRITE | 5.281 | 1.395 | 1.413 | 2.696 |
| W04 Expire rewards | WRITE | 4.486 | 1.649 | 1.730 | 2.622 |
| W05 Mark overdue bills | WRITE | 7.321 | 1.928 | 1.906 | 3.718 |

## Baseline plan observations

These are observations from the third raw plan for each query. The first run can be slower than later runs as pages warm in cache; the report retains all three timings rather than removing that variation.

| Query | Observed plan behavior |
|---|---|
| R01 | Parallel sequential scan of `transactions`, sequential scans of `vpas` for both sides of the `OR`, then a sort by initiation time. |
| R02 | Already uses primary-key index scans on `vpas` and `users`; very fast baseline. |
| R03 | Parallel sequential scan of `transactions` and sequential scan of `vpas`; `DATE(initiated_at)` applies a function to the filtered timestamp. |
| R04 | Parallel sequential scan of `transactions` for pending rows, followed by a sort on `initiated_at`. |
| R05 | Parallel sequential scan of `transactions` to find the merchant/date/status subset. |
| R06 | Parallel sequential scan of `transactions`, then join, aggregate and sort settlement totals. |
| R07 | Parallel sequential scan of `transactions` for failed payments, followed by VPA/account joins and aggregation sorts. |
| R08 | Sequential scan of `transactions`; grouping/sorting spills about 6.9 MB to disk. |
| R09 | Sequential scan of successful transactions; the window sort on payer, payee and time spills about 17.8 MB to disk, followed by another sort. |
| R10 | Sequential scan of all rewards for one user's status/expiry filter, then sort. |
| R11 | Sequential scan of rewards for status/expiry conditions, then sort. |
| R12 | Sequential scan of all bills for one user's status/date range, then sort. |
| R13 | Sequential scans of `merchants` and `transactions` for the anti-membership check. |
| R14 | Sequential scans of `transactions` and `vpas`, plus merchant lookups; date extraction is applied to `initiated_at`. |
| R15 | Parallel sequential scan of `transactions`, then merchant join, aggregate and rank/sorts by city. |
| R16 | Sequential scan of the small `disputes` table and primary-key lookups in `transactions`; fast baseline. |
| R17 | Parallel sequential scan of P2M transactions followed by merchant aggregation. |
| R18 | Parallel sequential scan of transactions plus sequential scans/hash joins over `vpas` and `users`, then grouping and sort. |
| R19 | Two correlated transaction subqueries each scan `transactions` for each of 239 merchants; the repeated scans dominate the roughly 4.2 second runtime. |
| R20 | Parallel sequential scan of `transactions`; `initiated_at::date` is filtered and grouped, then sorted. |
| R21 | Sequential scan of 3,000 merchants for the substring search; table is small and baseline is about 1 ms. |
| R22 | Sequential scan of all 53,333 VPAs for a single user's accounts; the bank-account side uses an index. |
| R23 | Sequential scan of all transactions, full newest-first sort spills about 14.2 MB to disk, then `OFFSET 200000` discards most rows. |
| R24 | Already uses the unique index on `transactions.upi_ref`; very fast baseline. |
| R25 | Sequential scans of transactions and VPAs plus bank-account joins; filters transaction time and groups by bank. |
| W01 | Insert plan has no scan node; most of the observed cost is the write itself. |
| W02 | Primary-key lookup is used for the update, but finding the oldest pending transaction filters nearly the full transaction table. |
| W03 | Sequential scan of rewards to find the oldest qualifying card, followed by a primary-key update. |
| W04 | Sequential scan of rewards to find expired unscratched rows. |
| W05 | Sequential scan of bills to find due unpaid rows past the cutoff. |

These are baseline observations, not an optimization claim. CP3 before/after values belong in [`04_optimization_report.md`](04_optimization_report.md) after the optimized workload has been benchmarked.
