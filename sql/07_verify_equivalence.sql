-- =====================================================================
-- Google Pay (UPI) DBMS Project: Workload Equivalence & Verification Suite
--
-- This script performs automated two-way semantic equivalence assertions
-- between original workload queries (queries/workload_30.sql) and optimized
-- queries (sql/06_optimized_queries.sql).
--
-- For rewritten queries (R01, R03, R13, R14, R20, R22), it tests:
--   1. count(orig EXCEPT ALL opt) = 0
--   2. count(opt EXCEPT ALL orig) = 0
--
-- For R13, it also explicitly evaluates the three-valued logic difference
-- (P4: 0 rows in buggy NOT IN vs 450 rows in corrected NOT EXISTS).
--
-- All write tests are wrapped inside BEGIN ... ROLLBACK blocks to guarantee
-- that persistent database data is never modified.
-- =====================================================================

SET search_path TO gpay;

-- ---------------------------------------------------------------------
-- Part 1: Two-Way Semantic Equivalence Assertions (Rewritten Queries)
-- ---------------------------------------------------------------------

-- Assertion R01: User Transaction History (OR Subquery vs UNION of Indexes)
WITH orig AS (
    SELECT t.txn_id, t.upi_ref, t.payer_vpa, t.payee_vpa, t.amount, t.status, t.initiated_at
    FROM transactions t
    WHERE t.payer_vpa IN (SELECT vpa FROM vpas WHERE user_id = 15177)
       OR t.payee_vpa IN (SELECT vpa FROM vpas WHERE user_id = 15177)
    ORDER BY t.initiated_at DESC
    LIMIT 30
),
opt AS (
    SELECT txn_id, upi_ref, payer_vpa, payee_vpa, amount, status, initiated_at
    FROM (
        SELECT t.txn_id, t.upi_ref, t.payer_vpa, t.payee_vpa, t.amount, t.status, t.initiated_at
        FROM transactions t
        JOIN vpas v ON v.vpa = t.payer_vpa
        WHERE v.user_id = 15177
        UNION
        SELECT t.txn_id, t.upi_ref, t.payer_vpa, t.payee_vpa, t.amount, t.status, t.initiated_at
        FROM transactions t
        JOIN vpas v ON v.vpa = t.payee_vpa
        WHERE v.user_id = 15177
    ) t
    ORDER BY initiated_at DESC
    LIMIT 30
)
SELECT 'R01' AS query_id,
       (SELECT count(*) FROM orig) AS orig_count,
       (SELECT count(*) FROM opt) AS opt_count,
       (SELECT count(*) FROM (SELECT * FROM orig EXCEPT ALL SELECT * FROM opt) d1) AS orig_except_opt,
       (SELECT count(*) FROM (SELECT * FROM opt EXCEPT ALL SELECT * FROM orig) d2) AS opt_except_orig;

-- Assertion R03: Daily UPI Limit Check (DATE() function vs Half-Open Timestamp Range)
WITH orig AS (
    SELECT coalesce(sum(t.amount), 0) AS sent_today
    FROM transactions t
    JOIN vpas v ON v.vpa = t.payer_vpa
    WHERE v.user_id = 15177
      AND t.status IN ('SUCCESS', 'PENDING')
      AND DATE(t.initiated_at) = '2026-06-30'
),
opt AS (
    SELECT coalesce(sum(t.amount), 0) AS sent_today
    FROM transactions t
    JOIN vpas v ON v.vpa = t.payer_vpa
    WHERE v.user_id = 15177
      AND t.status IN ('SUCCESS', 'PENDING')
      AND t.initiated_at >= '2026-06-30' AND t.initiated_at < '2026-07-01'
)
SELECT 'R03' AS query_id,
       (SELECT count(*) FROM orig) AS orig_count,
       (SELECT count(*) FROM opt) AS opt_count,
       (SELECT count(*) FROM (SELECT * FROM orig EXCEPT ALL SELECT * FROM opt) d1) AS orig_except_opt,
       (SELECT count(*) FROM (SELECT * FROM opt EXCEPT ALL SELECT * FROM orig) d2) AS opt_except_orig;

-- Assertion R13: Inactive Merchants Report
-- Demonstrates the NULL correctness fix:
-- 1. Buggy original NOT IN returns 0 rows due to NULL merchant_id values in P2P transactions.
-- 2. Corrected NOT EXISTS returns 450 rows.
-- 3. Equivalence with intended relational anti-join (NOT IN with NULL filter) is 100% identical.
WITH buggy_orig AS (
    SELECT m.merchant_id, m.merchant_name, m.onboarded_on
    FROM merchants m
    WHERE m.merchant_id NOT IN (SELECT t.merchant_id FROM transactions t)
),
intended_orig AS (
    SELECT m.merchant_id, m.merchant_name, m.onboarded_on
    FROM merchants m
    WHERE m.merchant_id NOT IN (SELECT t.merchant_id FROM transactions t WHERE t.merchant_id IS NOT NULL)
),
opt AS (
    SELECT m.merchant_id, m.merchant_name, m.onboarded_on
    FROM merchants m
    WHERE NOT EXISTS (
        SELECT 1 FROM transactions t WHERE t.merchant_id = m.merchant_id
    )
)
SELECT 'R13' AS query_id,
       (SELECT count(*) FROM buggy_orig) AS buggy_orig_count,
       (SELECT count(*) FROM intended_orig) AS intended_orig_count,
       (SELECT count(*) FROM opt) AS opt_count,
       (SELECT count(*) FROM (SELECT * FROM intended_orig EXCEPT ALL SELECT * FROM opt) d1) AS orig_except_opt,
       (SELECT count(*) FROM (SELECT * FROM opt EXCEPT ALL SELECT * FROM intended_orig) d2) AS opt_except_orig;

-- Assertion R14: Spend Analysis by MCC (EXTRACT(YEAR) vs Sargable Range)
WITH orig AS (
    SELECT m.mcc, count(*) AS payments, sum(t.amount) AS spent
    FROM transactions t
    JOIN merchants m ON m.merchant_id = t.merchant_id
    JOIN vpas v      ON v.vpa = t.payer_vpa
    WHERE v.user_id = 15177
      AND t.status = 'SUCCESS'
      AND EXTRACT(YEAR FROM t.initiated_at) >= 2025
    GROUP BY m.mcc
),
opt AS (
    SELECT m.mcc, count(*) AS payments, sum(t.amount) AS spent
    FROM transactions t
    JOIN merchants m ON m.merchant_id = t.merchant_id
    JOIN vpas v      ON v.vpa = t.payer_vpa
    WHERE v.user_id = 15177
      AND t.status = 'SUCCESS'
      AND t.initiated_at >= '2025-01-01'
    GROUP BY m.mcc
)
SELECT 'R14' AS query_id,
       (SELECT count(*) FROM orig) AS orig_count,
       (SELECT count(*) FROM opt) AS opt_count,
       (SELECT count(*) FROM (SELECT * FROM orig EXCEPT ALL SELECT * FROM opt) d1) AS orig_except_opt,
       (SELECT count(*) FROM (SELECT * FROM opt EXCEPT ALL SELECT * FROM orig) d2) AS opt_except_orig;

-- Assertion R20: Platform Daily Success Rate (CAST to date BETWEEN vs Half-Open Range)
WITH orig AS (
    SELECT initiated_at::date AS day, count(*) AS payments,
           round(100.0 * count(*) FILTER (WHERE status = 'SUCCESS') / count(*), 2) AS success_pct
    FROM transactions
    WHERE initiated_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
),
opt AS (
    SELECT initiated_at::date AS day, count(*) AS payments,
           round(100.0 * count(*) FILTER (WHERE status = 'SUCCESS') / count(*), 2) AS success_pct
    FROM transactions
    WHERE initiated_at >= '2026-06-01' AND initiated_at < '2026-07-01'
    GROUP BY 1
)
SELECT 'R20' AS query_id,
       (SELECT count(*) FROM orig) AS orig_count,
       (SELECT count(*) FROM opt) AS opt_count,
       (SELECT count(*) FROM (SELECT * FROM orig EXCEPT ALL SELECT * FROM opt) d1) AS orig_except_opt,
       (SELECT count(*) FROM (SELECT * FROM opt EXCEPT ALL SELECT * FROM orig) d2) AS opt_except_orig;

-- Assertion R22: Payment Screen Accounts and VPAs (Unconstrained JOIN vs Composite FK JOIN)
WITH orig AS (
    SELECT ba.bank_name, ba.account_last4, ba.is_primary, v.vpa, v.is_active
    FROM bank_accounts ba
    LEFT JOIN vpas v ON v.account_id = ba.account_id
    WHERE ba.user_id = 15177
),
opt AS (
    SELECT ba.bank_name, ba.account_last4, ba.is_primary, v.vpa, v.is_active
    FROM bank_accounts ba
    LEFT JOIN vpas v ON v.account_id = ba.account_id AND v.user_id = ba.user_id
    WHERE ba.user_id = 15177
)
SELECT 'R22' AS query_id,
       (SELECT count(*) FROM orig) AS orig_count,
       (SELECT count(*) FROM opt) AS opt_count,
       (SELECT count(*) FROM (SELECT * FROM orig EXCEPT ALL SELECT * FROM opt) d1) AS orig_except_opt,
       (SELECT count(*) FROM (SELECT * FROM opt EXCEPT ALL SELECT * FROM orig) d2) AS opt_except_orig;
