# CP2 baseline timings

**Run date:** 25 November 2026 · **Database:** `gpay_cp1` · **PostgreSQL:** 18.7
**Method:** repository benchmark script, `EXPLAIN (ANALYZE, BUFFERS)`, three runs per query. Write queries ran in transactions that were rolled back. Times below are milliseconds; averages are the arithmetic mean of the three raw `Execution Time` readings.

Raw plans and the generated average/median/min/max summary are in [`benchmarks/results/baseline/`](../benchmarks/results/baseline/). The original workload file was not modified.

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Transaction history: everything user 15177 sent or received, newest first | READ | 26.842 | 19.593 | 16.150 | 20.862 |
| R02: "Pay to UPI ID": check that the entered VPA exists and is active | READ | 0.031 | 0.044 | 0.030 | 0.035 |
| R03: UPI limit check: total successfully sent by user 15177 on 30 June 2026 (limit ₹1,00,000/day) | READ | 12.928 | 12.884 | 12.424 | 12.745 |
| R04: Reconciliation: payments still PENDING more than 15 minutes after 23:59 on 30 Jun 2026 | READ | 7.731 | 7.762 | 7.722 | 7.738 |
| R05: Google Pay for Business: hourly collections of merchant 2 on 29 June 2026 | READ | 7.185 | 7.320 | 7.207 | 7.237 |
| R06: Settlement: amount to settle to every merchant for 29 June 2026 | READ | 7.233 | 7.808 | 7.275 | 7.439 |
| R07: Bank health: failure codes per payer bank in the last 7 days | READ | 7.807 | 7.984 | 7.678 | 7.823 |
| R08: Fraud: VPAs that received P2P money from 5+ different people on the same day | READ | 127.827 | 130.570 | 126.583 | 128.327 |
| R09: Fraud: repeated payments—same payer to the same payee within 10 minutes of the previous one | READ | 277.354 | 273.020 | 269.561 | 273.312 |
| R10: Rewards tab: user 15177's unscratched cards that have not expired | READ | 1.655 | 1.618 | 1.566 | 1.613 |
| R11: Notification job: unscratched rewards that expire in the first 3 days of July | READ | 1.858 | 1.715 | 1.848 | 1.807 |
| R12: Bill reminders: user 1072's unpaid bills due in the next 7 days | READ | 1.775 | 1.305 | 1.243 | 1.441 |
| R13: Merchant success team: merchants who have never received a payment (to call and help them) | READ | 23.899 | 23.778 | 24.342 | 24.006 |
| R14: Spend analysis: user 15177's 2026 spending per merchant category code (MCC) | READ | 17.485 | 18.064 | 17.733 | 17.761 |
| R15: Business insights: top 10 merchants by June 2026 GMV in each city | READ | 10.214 | 10.290 | 10.081 | 10.195 |
| R16: Disputes desk: disputes open for more than 7 days (SLA breached) | READ | 0.303 | 0.303 | 0.296 | 0.301 |
| R17: Merchant risk: refund rate per merchant (at least 30 payments) | READ | 11.809 | 11.976 | 11.884 | 11.890 |
| R18: Compliance: users without verified KYC who have successfully sent ₹10,000+ in total | READ | 24.728 | 24.799 | 25.237 | 24.921 |
| R19: Merchant report: last payment time and successful payment count of every verified Bengaluru merchant | READ | 4731.299 | 4741.654 | 4766.310 | 4746.421 |
| R20: Platform health: daily success rate in June 2026 | READ | 10.586 | 10.397 | 10.539 | 10.507 |
| R21: "Search businesses": merchants with "chai" in their name | READ | 1.077 | 1.019 | 1.055 | 1.050 |
| R22: Payment screen: user 15177's primary bank account and all their UPI IDs | READ | 3.359 | 3.655 | 3.460 | 3.491 |
| R23: Operations console: all transactions, newest first, page 8,001 (25 per page) | READ | 61.527 | 61.729 | 61.461 | 61.572 |
| R24: Customer support: find a payment by its UPI reference number | READ | 0.032 | 0.035 | 0.038 | 0.035 |
| R25: Bank health: average seconds from initiation to completion per payer bank (June 2026) | READ | 21.688 | 21.851 | 21.754 | 21.764 |
| W01: Pay: user 15177 starts a ₹250 payment to merchant 2 (PENDING until the bank confirms) | WRITE | 0.620 | 0.550 | 0.598 | 0.589 |
| W02: Bank callback: mark the oldest PENDING payment as successful | WRITE | 23.447 | 20.312 | 20.451 | 21.403 |
| W03: Scratch card: user 15177 scratches their oldest unscratched card | WRITE | 1.680 | 1.549 | 1.586 | 1.605 |
| W04: Nightly job (run at 00:00 on 4 Jul 2026): expire every reward whose time is up | WRITE | 1.949 | 1.980 | 1.986 | 1.972 |
| W05: Nightly job: bills past their due date and still unpaid become OVERDUE | WRITE | 2.372 | 2.165 | 2.176 | 2.238 |
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
