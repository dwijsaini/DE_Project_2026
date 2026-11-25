-- =====================================================================
-- Google Pay (UPI) DBMS Project: CP3 Optimized Workload
--   R01–R25 : read queries  (25)
--   W01–W05 : write queries (5)
--
-- Optimized query set preserving original semantics, query order, and markers.
-- =====================================================================
SET search_path TO gpay;
BEGIN;

-- @R01
-- Transaction history: everything user 15177 sent or received, newest first
-- Optimized: Rewritten with UNION instead of OR across payer_vpa and payee_vpa.
-- This allows both branches to use the respective (payer_vpa, initiated_at DESC)
-- and (payee_vpa, initiated_at DESC) indexes with idx_vpas_user_id_vpa, avoiding
-- a full-table index scan over 250k rows.
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
LIMIT 30;

-- @R02
-- "Pay to UPI ID": check that the entered VPA exists and is active
SELECT v.vpa, u.full_name, v.is_active
FROM vpas v
JOIN users u ON u.user_id = v.user_id
WHERE v.vpa = 'aditya.gupta15177@okhdfcbank';

-- @R03
-- UPI limit check: total successfully sent by user 15177 on 30 June 2026 (limit ₹1,00,000/day)
-- Optimized: Replaced non-sargable DATE(t.initiated_at) with a half-open timestamp range.
-- This enables an index range scan on idx_transactions_payer_vpa_initiated_desc while
-- preserving exact session-time-zone semantics.
SELECT coalesce(sum(t.amount), 0) AS sent_today
FROM transactions t
JOIN vpas v ON v.vpa = t.payer_vpa
WHERE v.user_id = 15177
  AND t.status IN ('SUCCESS', 'PENDING')
  AND t.initiated_at >= '2026-06-30' AND t.initiated_at < '2026-07-01';

-- @R04
-- Reconciliation: payments still PENDING more than 15 minutes after 23:59 on 30 Jun 2026
SELECT txn_id, upi_ref, payer_vpa, amount, initiated_at
FROM transactions
WHERE status = 'PENDING'
  AND initiated_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '15 minutes'
ORDER BY initiated_at;

-- @R05
-- Google Pay for Business: hourly collections of merchant 2 on 29 June 2026
SELECT EXTRACT(HOUR FROM initiated_at) AS hour, count(*) AS payments, sum(amount) AS collected
FROM transactions
WHERE merchant_id = 2
  AND status = 'SUCCESS'
  AND initiated_at >= '2026-06-29' AND initiated_at < '2026-06-30'
GROUP BY 1
ORDER BY 1;

-- @R06
-- Settlement: amount to settle to every merchant for 29 June 2026
SELECT m.merchant_id, m.merchant_name, count(*) AS payments, sum(t.amount) AS settle_amount
FROM transactions t
JOIN merchants m ON m.merchant_id = t.merchant_id
WHERE t.status = 'SUCCESS'
  AND t.initiated_at >= '2026-06-29' AND t.initiated_at < '2026-06-30'
GROUP BY m.merchant_id, m.merchant_name
ORDER BY settle_amount DESC;

-- @R07
-- Bank health: failure codes per payer bank in the last 7 days
SELECT ba.bank_name, t.failure_code, count(*) AS failures
FROM transactions t
JOIN vpas v           ON v.vpa = t.payer_vpa
JOIN bank_accounts ba ON ba.account_id = v.account_id
WHERE t.status = 'FAILED'
  AND t.initiated_at >= '2026-06-24'
GROUP BY ba.bank_name, t.failure_code
ORDER BY failures DESC;

-- @R08
-- Fraud: VPAs that received P2P money from 5+ different people on the same day
SELECT payee_vpa, initiated_at::date AS day, count(DISTINCT payer_vpa) AS distinct_payers, sum(amount) AS received
FROM transactions
WHERE txn_type = 'P2P' AND status = 'SUCCESS'
GROUP BY payee_vpa, initiated_at::date
HAVING count(DISTINCT payer_vpa) >= 5
ORDER BY distinct_payers DESC;

-- @R09
-- Fraud: repeated payments—same payer to the same payee within 10 minutes of the previous one
-- Optimization note: The index idx_transactions_success_payer_payee_initiated provides pre-sorted
-- input for PARTITION BY payer_vpa, payee_vpa ORDER BY initiated_at, eliminating the baseline
-- 17.8 MB disk spill. The query logic is preserved to maintain exact LAG semantics.
SELECT *
FROM (
    SELECT txn_id, payer_vpa, payee_vpa, amount, initiated_at,
           initiated_at - lag(initiated_at) OVER (PARTITION BY payer_vpa, payee_vpa ORDER BY initiated_at) AS gap
    FROM transactions
    WHERE status = 'SUCCESS'
) t
WHERE gap < interval '10 minutes'
ORDER BY initiated_at DESC;

-- @R10
-- Rewards tab: user 15177's unscratched cards that have not expired
SELECT reward_id, reward_type, issued_at, expires_at
FROM rewards
WHERE user_id = 15177 AND status = 'UNSCRATCHED'
  AND expires_at > '2026-06-30 23:59:00+05:30'
ORDER BY expires_at;

-- @R11
-- Notification job: unscratched rewards that expire in the first 3 days of July
SELECT reward_id, user_id, expires_at
FROM rewards
WHERE status = 'UNSCRATCHED'
  AND expires_at < '2026-07-04'
ORDER BY expires_at;

-- @R12
-- Bill reminders: user 1072's unpaid bills due in the next 7 days
SELECT bill_id, biller_name, amount, due_date
FROM bill_payments
WHERE user_id = 1072 AND status = 'DUE'
  AND due_date BETWEEN '2026-07-01' AND '2026-07-07'
ORDER BY due_date;

-- @R13
-- Merchant success team: merchants who have never received a payment (to call and help them)
-- Correctness Fix: Replaced NOT IN with NOT EXISTS.
-- In SQL three-valued logic, NOT IN with a subquery containing NULLs (from P2P transactions
-- where merchant_id IS NULL) evaluates to UNKNOWN for all rows, incorrectly returning 0 merchants.
-- NOT EXISTS correctly checks for non-existence of matching merchant payments and returns 450 rows,
-- while utilizing idx_transactions_merchant_initiated for a high-performance anti-join.
SELECT m.merchant_id, m.merchant_name, m.onboarded_on
FROM merchants m
WHERE NOT EXISTS (
    SELECT 1 FROM transactions t WHERE t.merchant_id = m.merchant_id
);

-- @R14
-- Spend analysis: user 15177's 2026 spending per merchant category code (MCC)
-- Optimized: Replaced EXTRACT(YEAR FROM ...) >= 2025 with sargable range initiated_at >= '2025-01-01'.
-- This pushes the timestamp condition directly into the index scan on
-- idx_transactions_success_payer_payee_initiated while maintaining session-time-zone semantics.
SELECT m.mcc, count(*) AS payments, sum(t.amount) AS spent
FROM transactions t
JOIN merchants m ON m.merchant_id = t.merchant_id
JOIN vpas v      ON v.vpa = t.payer_vpa
WHERE v.user_id = 15177
  AND t.status = 'SUCCESS'
  AND t.initiated_at >= '2025-01-01'
GROUP BY m.mcc
ORDER BY spent DESC;

-- @R15
-- Business insights: top 10 merchants by June 2026 GMV in each city
SELECT *
FROM (
    SELECT m.city_id, m.merchant_id, m.merchant_name, sum(t.amount) AS gmv,
           RANK() OVER (PARTITION BY m.city_id ORDER BY sum(t.amount) DESC) AS rnk
    FROM transactions t
    JOIN merchants m ON m.merchant_id = t.merchant_id
    WHERE t.status = 'SUCCESS'
      AND t.initiated_at >= '2026-06-01' AND t.initiated_at < '2026-07-01'
    GROUP BY m.city_id, m.merchant_id, m.merchant_name
) r
WHERE rnk <= 10
ORDER BY city_id, rnk;

-- @R16
-- Disputes desk: disputes open for more than 7 days (SLA breached)
SELECT d.dispute_id, d.reason, d.raised_at, t.upi_ref, t.amount
FROM disputes d
JOIN transactions t ON t.txn_id = d.txn_id
WHERE d.status = 'OPEN'
  AND d.raised_at < '2026-06-23'
ORDER BY d.raised_at;

-- @R17
-- Merchant risk: refund rate per merchant (at least 30 payments)
SELECT merchant_id, count(*) AS payments,
       round(100.0 * count(*) FILTER (WHERE status = 'REFUNDED') / count(*), 2) AS refund_pct
FROM transactions
WHERE txn_type = 'P2M'
GROUP BY merchant_id
HAVING count(*) >= 30
ORDER BY refund_pct DESC
LIMIT 20;

-- @R18
-- Compliance: users without verified KYC who have successfully sent ₹10,000+ in total
SELECT u.user_id, u.full_name, u.kyc_status, sum(t.amount) AS total_sent
FROM users u
JOIN vpas v         ON v.user_id = u.user_id
JOIN transactions t ON t.payer_vpa = v.vpa AND t.status = 'SUCCESS'
WHERE u.kyc_status <> 'VERIFIED'
GROUP BY u.user_id, u.full_name, u.kyc_status
HAVING sum(t.amount) >= 10000
ORDER BY total_sent DESC;

-- @R19
-- Merchant report: last payment time and successful payment count of every verified Bengaluru merchant
-- Optimization note: Correlated subqueries are optimized via dedicated partial indexes
-- idx_transactions_merchant_initiated and idx_transactions_success_merchant, allowing both
-- subqueries to execute as pure Index Only Scans with 0 table heap fetches for max() and fast
-- index counting for the 239 verified merchants. Rewriting to JOIN or LATERAL is demonstrated
-- to be significantly slower (19-37 ms) due to full table scans / heap visits.
SELECT m.merchant_id, m.merchant_name,
       (SELECT max(t.initiated_at) FROM transactions t WHERE t.merchant_id = m.merchant_id) AS last_payment_at,
       (SELECT count(*) FROM transactions t WHERE t.merchant_id = m.merchant_id AND t.status = 'SUCCESS') AS successful_payments
FROM merchants m
WHERE m.is_verified AND m.city_id = 1
ORDER BY successful_payments DESC;

-- @R20
-- Platform health: daily success rate in June 2026
-- Optimized: Replaced function call on timestamp initiated_at::date with sargable half-open range.
-- This enables an Index Scan using idx_transactions_initiated_desc, dropping buffer accesses
-- from 4,564 to 343 and runtime from 20.9 ms to 6.3 ms.
SELECT initiated_at::date AS day, count(*) AS payments,
       round(100.0 * count(*) FILTER (WHERE status = 'SUCCESS') / count(*), 2) AS success_pct
FROM transactions
WHERE initiated_at >= '2026-06-01' AND initiated_at < '2026-07-01'
GROUP BY 1
ORDER BY 1;

-- @R21
-- "Search businesses": merchants with "chai" in their name
SELECT merchant_id, merchant_name, merchant_vpa, city_id
FROM merchants
WHERE merchant_name ILIKE '%chai%'
ORDER BY merchant_name
LIMIT 25;

-- @R22
-- Payment screen: user 15177's primary bank account and all their UPI IDs
-- Optimized: Added v.user_id = ba.user_id to the join condition (guaranteed by the composite FK
-- on (account_id, user_id)). This allows the join to use the idx_vpas_user_id_vpa index
-- instead of scanning the full bank_accounts table; the user-scoped covering index keeps this path selective at scale.
SELECT ba.bank_name, ba.account_last4, ba.is_primary, v.vpa, v.is_active
FROM bank_accounts ba
LEFT JOIN vpas v ON v.account_id = ba.account_id AND v.user_id = ba.user_id
WHERE ba.user_id = 15177
ORDER BY ba.is_primary DESC;

-- @R23
-- Operations console: all transactions, newest first, page 8,001 (25 per page)
SELECT txn_id, upi_ref, txn_type, amount, status, initiated_at
FROM transactions
ORDER BY initiated_at DESC
OFFSET 200000
LIMIT 25;

-- @R24
-- Customer support: find a payment by its UPI reference number
SELECT txn_id, payer_vpa, payee_vpa, amount, status, failure_code, initiated_at, completed_at
FROM transactions
WHERE upi_ref = '600977648064';

-- @R25
-- Bank health: average seconds from initiation to completion per payer bank (June 2026)
SELECT ba.bank_name,
       round(avg(EXTRACT(EPOCH FROM (t.completed_at - t.initiated_at))), 2) AS avg_seconds,
       count(*) AS payments
FROM transactions t
JOIN vpas v           ON v.vpa = t.payer_vpa
JOIN bank_accounts ba ON ba.account_id = v.account_id
WHERE t.completed_at IS NOT NULL
  AND t.initiated_at >= '2026-06-01'
GROUP BY ba.bank_name
ORDER BY avg_seconds DESC;

-- @W01
-- Pay: user 15177 starts a ₹250 payment to merchant 2 (PENDING until the bank confirms)
INSERT INTO transactions (txn_id, upi_ref, txn_type, payer_vpa, payee_vpa, merchant_id, amount, initiated_at, status)
VALUES (90000001, '999900000001', 'P2M', 'aditya.gupta15177@okhdfcbank', 'balaji2@okbizaxis', 2, 250.00,
        '2026-07-01 09:00:00+05:30', 'PENDING');

-- @W02
-- Bank callback: mark the oldest PENDING payment as successful
UPDATE transactions
SET status = 'SUCCESS', completed_at = initiated_at + interval '4 seconds'
WHERE txn_id = (SELECT min(txn_id) FROM transactions WHERE status = 'PENDING');

-- @W03
-- Scratch card: user 15177 scratches their oldest unscratched card
UPDATE rewards
SET status = 'CREDITED', credited_at = '2026-07-01 09:05:00+05:30'
WHERE reward_id = (SELECT min(reward_id) FROM rewards WHERE user_id = 15177 AND status = 'UNSCRATCHED');

-- @W04
-- Nightly job (run at 00:00 on 4 Jul 2026): expire every reward whose time is up
UPDATE rewards
SET status = 'EXPIRED'
WHERE status = 'UNSCRATCHED'
  AND expires_at < '2026-07-04 00:00:00+05:30';

-- @W05
-- Nightly job: bills past their due date and still unpaid become OVERDUE
UPDATE bill_payments
SET status = 'OVERDUE'
WHERE status = 'DUE'
  AND due_date < '2026-07-05';

-- @END
ROLLBACK;
