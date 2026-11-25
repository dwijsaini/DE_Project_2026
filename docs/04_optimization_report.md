# CP3 optimization report

**Status: completed and measured.** The original workload and baseline remain unchanged. The index definitions are in [`../sql/05_indexes.sql`](../sql/05_indexes.sql), and the optimized query set is in [`../sql/06_optimized_queries.sql`](../sql/06_optimized_queries.sql). PostgreSQL 18.7 on the same local machine was used for the three-run averages. Baseline plans are under [`../benchmarks/results/baseline/`](../benchmarks/results/baseline/); optimized seed-data plans are under [`../benchmarks/results/optimized/`](../benchmarks/results/optimized/). The benchmark script writes to `after/`; `optimized/` is the matching submission copy required by the checkpoint list.

| Query | Before (ms) | Problem in baseline plan | Optimization applied | After (ms) | Improvement | Same result? |
|---|---:|---|---|---:|---:|:---:|
| R01 | 24.783 | Parallel scan of all transactions; two VPA scans for the OR predicate; sort by time. | Split the OR lookup into payer and payee index seeks; UNION removes duplicate transaction rows. | 0.117 | +99.5% | Yes |
| R02 | 0.291 | Uses VPA and user primary-key indexes; already fast. | No rewrite; the existing VPA and user primary-key lookups are already selective. | 0.128 | +56.0% | Yes |
| R03 | 11.761 | Parallel transaction scan plus VPA scan; `DATE(initiated_at)` filter. | Replace DATE(timestamp) with a half-open date range; add user/VPA and partial payer/time indexes. | 0.048 | +99.6% | Yes |
| R04 | 7.432 | Parallel transaction scan for pending rows, then sort by initiation time. | Add a partial pending/time index so the old pending rows can be filtered and ordered. | 0.060 | +99.2% | Yes |
| R05 | 6.667 | Parallel transaction scan for merchant, status, and date range. | Add a partial (merchant,time) success index with amount included. | 0.117 | +98.2% | Yes |
| R06 | 6.969 | Parallel transaction scan, merchant join, aggregation, and settlement sort. | Add a partial (time,merchant) success covering index for settlement aggregation. | 0.489 | +93.0% | Yes |
| R07 | 10.054 | Parallel transaction scan for failures, then VPA/account joins and aggregation sorts. | Add a partial failed/time covering index before the VPA and account joins. | 4.385 | +56.4% | Yes |
| R08 | 119.070 | Transaction scan and grouping sort spill about 6.9 MB to disk. | Add a partial P2P-success payee/time covering index; aggregation still reads qualifying rows. | 45.385 | +61.9% | Yes |
| R09 | 262.420 | Transaction scan and window sort spill about 17.8 MB to disk; another sort follows. | Add an ordered partial success index on payer,payee,time for the lag window. | 55.628 | +78.8% | Yes |
| R10 | 2.452 | Scans all rewards for one user's status/expiry filter, then sorts. | Add a partial user/expiry index for unexpired unscratched rewards. | 0.046 | +98.1% | Yes |
| R11 | 1.680 | Scans rewards for status/expiry filter, then sorts. | Add a partial expiry index for unscratched reward scans. | 0.052 | +96.9% | Yes |
| R12 | 1.761 | Scans all bills for one user's status/date filter, then sorts. | Add a partial user/due-date index for due bills. | 0.047 | +97.3% | Yes |
| R13 | 21.979 | Scans merchants and transactions. `NOT IN` sees NULL `merchant_id` values from P2P rows, so the original query returns no merchants; investigate as a correctness bug. | Replace NULL-sensitive NOT IN with NOT EXISTS and probe the merchant transaction index (correctness fix). | 1.354 | +93.8% | No* |
| R14 | 17.336 | Scans transactions and VPAs; applies year extraction to transaction timestamps before grouping. | Replace EXTRACT(YEAR) with a timestamp lower bound; use user/VPA and partial success/payer/time indexes. | 0.150 | +99.1% | Yes |
| R15 | 9.235 | Parallel transaction scan, merchant join, aggregation, and ranking/sorts by city. | Add a partial success/time/merchant covering index for the June aggregation. | 3.041 | +67.1% | Yes |
| R16 | 0.805 | Scans the small disputes table and uses transaction primary-key lookups; already fast. | Add a partial open-dispute/raised-time index. | 0.169 | +79.0% | Yes |
| R17 | 11.455 | Parallel scan of P2M transactions followed by merchant aggregation. | Add a partial P2M/merchant index including status. | 9.121 | +20.4% | Yes |
| R18 | 23.201 | Parallel transaction scan plus VPA/user scans and joins, grouping, and sort. | Add a partial success/payer covering index for the successful-send aggregate. | 17.935 | +22.7% | Yes |
| R19 | 4,185.057 | Two correlated subqueries each rescan transactions for each of 239 merchants. | Replace two per-merchant correlated subqueries with one grouped transaction aggregate. | 10.435 | +99.8% | Yes |
| R20 | 9.869 | Parallel transaction scan; casts timestamps to dates for filter/grouping, then sorts. | Replace timestamp-to-date filtering with a half-open date range and a time/status covering index. | 2.107 | +78.7% | Yes |
| R21 | 1.009 | Scans 3,000 merchants for substring search; small table and low baseline time. | Add a trigram GIN index for the contains search; query text stays unchanged. | 0.257 | +74.5% | Yes |
| R22 | 3.497 | Scans all 53,333 VPAs for one user's account view; bank-account lookup uses an index. | Add user/primary and VPA/account covering indexes for the building/account lookup. | 0.037 | +98.9% | Yes |
| R23 | 59.579 | Scans and sorts all transactions; sort spills about 14.2 MB, then OFFSET discards 200,000 rows. | Use a stable (initiated_at,txn_id) keyset boundary and a descending composite index; standalone test derives the cursor with OFFSET. | 38.892 | +34.7% | Yes |
| R24 | 0.616 | Uses the unique UPI-reference index; already fast. | No rewrite; the unique UPI-reference index is already selective. | 0.206 | +66.6% | Yes |
| R25 | 20.972 | Scans transactions and VPAs, joins bank accounts, then groups by bank. | Add a partial completed-payment/time covering index for the bank aggregation. | 13.519 | +35.5% | Yes |
| W01 | 2.014 | Insert-only plan has no scan node; write overhead still needs comparison after indexing. | No rewrite; the test insert is executed inside BEGIN/ROLLBACK. Index maintenance is part of its measured cost. | 1.196 | +40.6% | — |
| W02 | 20.489 | Finds the oldest pending row by filtering nearly the full transaction table before a primary-key update. | Add a partial pending/txn_id index to find the oldest pending ID before the primary-key update. | 0.485 | +97.6% | — |
| W03 | 2.696 | Scans rewards to find the oldest qualifying card, then updates by primary key. | Add a partial user/reward-ID index for the oldest unscratched card. | 0.353 | +86.9% | — |
| W04 | 2.622 | Scans rewards for expired, unscratched rows. | Add a partial expiry index for the expired unscratched reward update. | 0.395 | +84.9% | — |
| W05 | 3.718 | Scans bills for due unpaid rows past the cutoff. | Add a partial due-date index for overdue unpaid bills. | 1.590 | +57.2% | — |
| **Total of 30 means** | **4,851.489** | Sum of per-query averages; dominated by R19 before optimization. | — | **207.744** | **+95.7%** | — |

`Improvement = (before − after) / before × 100`. “Same result” was checked by comparing the ordered result rows on the seed database. All 24 unchanged read queries match, including R23's page output. **R13 is the deliberate exception:** the original returns zero rows because `NOT IN` compares against NULL merchant IDs on P2P transactions; the corrected `NOT EXISTS` returns 450 never-used merchants. The five W queries were run under the benchmark's `BEGIN`/`ROLLBACK` wrapper; no test writes were retained.

## Largest measured improvements and plans

| Query | Before → after | Plan change | Raw plans |
|---|---:|---|---|
| R19 | 4,185.057 → 10.435 ms (99.8%) | Two correlated transaction rescans per merchant became one grouped transaction scan using `idx_txn_merchant_time_status`. | [`baseline/R19.txt`](../benchmarks/results/baseline/R19.txt), [`optimized/R19.txt`](../benchmarks/results/optimized/R19.txt) |
| W02 | 20.489 → 0.485 ms (97.6%) | Finding the oldest pending transaction uses the partial `idx_txn_pending_id`; update still uses the primary key. | [`baseline/W02.txt`](../benchmarks/results/baseline/W02.txt), [`optimized/W02.txt`](../benchmarks/results/optimized/W02.txt) |
| R03 | 11.761 → 0.048 ms (99.6%) | Date range and partial payer/time index replace the timestamp function and full transaction scan. | [`baseline/R03.txt`](../benchmarks/results/baseline/R03.txt), [`optimized/R03.txt`](../benchmarks/results/optimized/R03.txt) |
| R04 | 7.432 → 0.060 ms (99.2%) | Pending-only rows use a partial index rather than scanning the transaction table. | [`baseline/R04.txt`](../benchmarks/results/baseline/R04.txt), [`optimized/R04.txt`](../benchmarks/results/optimized/R04.txt) |
| R10 | 2.452 → 0.046 ms (98.1%) | User and expiry search uses the partial unscratched-reward index. | [`baseline/R10.txt`](../benchmarks/results/baseline/R10.txt), [`optimized/R10.txt`](../benchmarks/results/optimized/R10.txt) |

Other broad scans remain in analytical queries that must aggregate many rows. R08 and R09 improved but still need to read most qualifying transactions. R02 and R24 were already efficient and were left unchanged. No W query's three-run average increased, although indexes still add storage and insert/update maintenance; timings are small and sensitive to cache state.

## Added index storage on the large dataset

Sizes below are measured after the Phase 5 indexes were built. Percentage is each added index size divided by its table's heap size. These figures make the storage cost of covering indexes visible; they are not a claim that each individual index is the only usable index for its query.

| Index | Table | Index size | % of table heap |
|---|---|---:|---:|
| `idx_bank_accounts_user_primary` | `bank_accounts` | 53.95 MiB | 54.95% |
| `idx_bills_due_date` | `bill_payments` | 224 KiB | 0.38% |
| `idx_bills_due_user_date` | `bill_payments` | 1.42 MiB | 2.50% |
| `idx_disputes_open_raised` | `disputes` | 160 KiB | 2.23% |
| `idx_merchants_name_trgm` | `merchants` | 2.25 MiB | 39.13% |
| `idx_rewards_unscratched_expiry` | `rewards` | 352 KiB | 0.49% |
| `idx_rewards_unscratched_user_id` | `rewards` | 256 KiB | 0.36% |
| `idx_rewards_user_unscratched_expiry` | `rewards` | 688 KiB | 0.96% |
| `idx_txn_completed_time` | `transactions` | 307.84 MiB | 43.69% |
| `idx_txn_failed_time` | `transactions` | 14.20 MiB | 2.01% |
| `idx_txn_merchant` | `transactions` | 19.16 MiB | 2.72% |
| `idx_txn_merchant_success_time` | `transactions` | 180.10 MiB | 25.56% |
| `idx_txn_merchant_time_status` | `transactions` | 108.92 MiB | 15.46% |
| `idx_txn_ops_page` | `transactions` | 321.94 MiB | 45.69% |
| `idx_txn_p2m_merchant` | `transactions` | 84.36 MiB | 11.97% |
| `idx_txn_p2p_payee_time` | `transactions` | 181.73 MiB | 25.79% |
| `idx_txn_payee_time` | `transactions` | 577.75 MiB | 82.00% |
| `idx_txn_payer_daily_limit` | `transactions` | 328.30 MiB | 46.60% |
| `idx_txn_payer_success_time` | `transactions` | 328.13 MiB | 46.57% |
| `idx_txn_payer_time` | `transactions` | 577.92 MiB | 82.03% |
| `idx_txn_pending_id` | `transactions` | 72 KiB | 0.01% |
| `idx_txn_pending_time` | `transactions` | 216 KiB | 0.03% |
| `idx_txn_success_pair_time` | `transactions` | 444.16 MiB | 63.04% |
| `idx_txn_success_time_merchant` | `transactions` | 179.85 MiB | 25.53% |
| `idx_txn_time_status` | `transactions` | 151.27 MiB | 21.47% |
| `idx_vpas_account` | `vpas` | 52.83 MiB | 66.35% |
| `idx_vpas_user_vpa` | `vpas` | 61.20 MiB | 76.85% |

On the seed database the `transactions` heap is about 35 MiB with 200 MiB of total indexes. On the large database it is 705 MiB with about 3,806 MiB of added workload indexes; together with the existing primary-key and UPI-reference indexes, the table has about 4,064 MiB of indexes (4.0 GiB). At this size, index-only scans can reduce repeated heap reads, but adding all workload indexes trades substantial disk space and write amplification for read speed. Review this tradeoff before production deployment.
