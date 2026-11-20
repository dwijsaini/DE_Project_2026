# Raja CP3 query verification

**Method:** Compared committed baseline/optimized summary CSV values and inspected the corresponding committed raw plan files. These are existing recorded runs, not a fresh benchmark. A local PostgreSQL 18.7 server is reachable on port 5433. I loaded the seed into a scratch `gpay_cp1` database using the committed schema and loader; all nine target row counts printed successfully.

| Query | Baseline avg ms | Optimized avg ms | Change |
|---|---:|---:|---:|
| R01 | 24.783 | 0.264 | 98.93% faster |
| R03 | 11.761 | 0.071 | 99.40% faster |
| R14 | 17.336 | 0.210 | 98.79% faster |
| R20 | 9.869 | 5.721 | 42.03% faster |
| R22 | 3.497 | 1.215 | 65.26% faster |

## R13 correction

`sql/06_optimized_queries.sql` uses `NOT EXISTS` for the merchant anti-join. The existing optimization report records 450 results from the corrected query, versus zero from the prior `NOT IN` form because nullable merchant IDs propagate NULL into the subquery. The live scratch database anti-join returned 450 rows. The committed R13 optimized summary average is 6.470 ms; this scratch recount is a correctness check, not a fresh benchmark.

## Summary and raw-plan consistency

For the requested rewritten queries, the summary files contain one row each and each phase has its matching three-run raw-plan file. The optimized summary includes all 30 workload identifiers. Raw-plan execution-time averages for all requested queries match their corresponding CSV averages to three decimals. A fresh full 30-query benchmark was not rerun.

## Regression review

Among the reported candidates, R08 shows the largest optimized average at 259.517 ms, but its raw plan is a sequential scan on `transactions`. That scan is consistent with the query’s multi-column/day aggregation; the saved evidence alone does not justify a SQL rewrite. R17, R18, R21, and R25 have lower recorded averages and their plans do not establish a semantics-preserving rewrite opportunity. No workload SQL was changed.

## CP4 availability

`large_data.zip` is absent from this checkout. Consequently the optimized large-data workload and partition-pruning experiment remain pending. The existing branch `dwij/cp4-scalability-work` is remote; no partitioning files were modified or copied.
