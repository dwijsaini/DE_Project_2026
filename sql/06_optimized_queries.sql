-- Optimized Phase 4 workload. Keep query IDs aligned with workload_30.sql.
-- R13 fixes the original NULL-sensitive NOT IN bug (see report).
SET search_path TO gpay;
BEGIN;

-- @R01
-- Two indexed VPA lookups; UNION removes a transaction found on both sides.
SELECT txn_id, upi_ref, payer_vpa, payee_vpa, amount, status, initiated_at
FROM (
    SELECT t.txn_id, t.upi_ref, t.payer_vpa, t.payee_vpa, t.amount, t.status, t.initiated_at
    FROM vpas v JOIN transactions t ON t.payer_vpa = v.vpa
    WHERE v.user_id = 15177
    UNION
    SELECT t.txn_id, t.upi_ref, t.payer_vpa, t.payee_vpa, t.amount, t.status, t.initiated_at
    FROM vpas v JOIN transactions t ON t.payee_vpa = v.vpa
    WHERE v.user_id = 15177
) history
ORDER BY initiated_at DESC LIMIT 30;

-- @R02
SELECT v.vpa, u.full_name, v.is_active
FROM vpas v JOIN users u ON u.user_id = v.user_id
WHERE v.vpa = 'aditya.gupta15177@okhdfcbank';

-- @R03
SELECT coalesce(sum(t.amount), 0) AS sent_today
FROM vpas v JOIN transactions t ON t.payer_vpa = v.vpa
WHERE v.user_id = 15177
  AND t.status IN ('SUCCESS', 'PENDING')
  AND t.initiated_at >= DATE '2026-06-30'
  AND t.initiated_at < DATE '2026-07-01';

-- @R04
SELECT txn_id, upi_ref, payer_vpa, amount, initiated_at
FROM transactions
WHERE status = 'PENDING'
  AND initiated_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '15 minutes'
ORDER BY initiated_at;

-- @R05
SELECT EXTRACT(HOUR FROM initiated_at) AS hour, count(*) AS payments, sum(amount) AS collected
FROM transactions
WHERE merchant_id = 2 AND status = 'SUCCESS'
  AND initiated_at >= DATE '2026-06-29' AND initiated_at < DATE '2026-06-30'
GROUP BY 1 ORDER BY 1;

-- @R06
SELECT m.merchant_id, m.merchant_name, count(*) AS payments, sum(t.amount) AS settle_amount
FROM transactions t JOIN merchants m ON m.merchant_id = t.merchant_id
WHERE t.status = 'SUCCESS'
  AND t.initiated_at >= DATE '2026-06-29' AND t.initiated_at < DATE '2026-06-30'
GROUP BY m.merchant_id, m.merchant_name ORDER BY settle_amount DESC;

-- @R07
SELECT ba.bank_name, t.failure_code, count(*) AS failures
FROM transactions t
JOIN vpas v ON v.vpa = t.payer_vpa
JOIN bank_accounts ba ON ba.account_id = v.account_id
WHERE t.status = 'FAILED' AND t.initiated_at >= DATE '2026-06-24'
GROUP BY ba.bank_name, t.failure_code ORDER BY failures DESC;

-- @R08
SELECT payee_vpa, initiated_at::date AS day,
       count(DISTINCT payer_vpa) AS distinct_payers, sum(amount) AS received
FROM transactions
WHERE txn_type = 'P2P' AND status = 'SUCCESS'
GROUP BY payee_vpa, initiated_at::date
HAVING count(DISTINCT payer_vpa) >= 5
ORDER BY distinct_payers DESC;

-- @R09
SELECT * FROM (
    SELECT txn_id, payer_vpa, payee_vpa, amount, initiated_at,
           initiated_at - lag(initiated_at) OVER
             (PARTITION BY payer_vpa, payee_vpa ORDER BY initiated_at) AS gap
    FROM transactions WHERE status = 'SUCCESS'
) t
WHERE gap < interval '10 minutes'
ORDER BY initiated_at DESC;

-- @R10
SELECT reward_id, reward_type, issued_at, expires_at
FROM rewards
WHERE user_id = 15177 AND status = 'UNSCRATCHED'
  AND expires_at > TIMESTAMPTZ '2026-06-30 23:59:00+05:30'
ORDER BY expires_at;

-- @R11
SELECT reward_id, user_id, expires_at
FROM rewards
WHERE status = 'UNSCRATCHED' AND expires_at < DATE '2026-07-04'
ORDER BY expires_at;

-- @R12
SELECT bill_id, biller_name, amount, due_date
FROM bill_payments
WHERE user_id = 1072 AND status = 'DUE'
  AND due_date BETWEEN DATE '2026-07-01' AND DATE '2026-07-07'
ORDER BY due_date;

-- @R13
-- Correction: the original NOT IN sees NULL merchant_id values from P2P rows.
SELECT m.merchant_id, m.merchant_name, m.onboarded_on
FROM merchants m
WHERE NOT EXISTS (
    SELECT 1 FROM transactions t WHERE t.merchant_id = m.merchant_id
);

-- @R14
SELECT m.mcc, count(*) AS payments, sum(t.amount) AS spent
FROM vpas v
JOIN transactions t ON t.payer_vpa = v.vpa
JOIN merchants m ON m.merchant_id = t.merchant_id
WHERE v.user_id = 15177 AND t.status = 'SUCCESS'
  AND t.initiated_at >= TIMESTAMPTZ '2025-01-01 00:00:00'
GROUP BY m.mcc ORDER BY spent DESC;

-- @R15
SELECT * FROM (
    SELECT m.city_id, m.merchant_id, m.merchant_name, sum(t.amount) AS gmv,
           RANK() OVER (PARTITION BY m.city_id ORDER BY sum(t.amount) DESC) AS rnk
    FROM transactions t JOIN merchants m ON m.merchant_id = t.merchant_id
    WHERE t.status = 'SUCCESS'
      AND t.initiated_at >= DATE '2026-06-01' AND t.initiated_at < DATE '2026-07-01'
    GROUP BY m.city_id, m.merchant_id, m.merchant_name
) r
WHERE rnk <= 10 ORDER BY city_id, rnk;

-- @R16
SELECT d.dispute_id, d.reason, d.raised_at, t.upi_ref, t.amount
FROM disputes d JOIN transactions t ON t.txn_id = d.txn_id
WHERE d.status = 'OPEN' AND d.raised_at < DATE '2026-06-23'
ORDER BY d.raised_at;

-- @R17
SELECT merchant_id, count(*) AS payments,
       round(100.0 * count(*) FILTER (WHERE status = 'REFUNDED') / count(*), 2) AS refund_pct
FROM transactions WHERE txn_type = 'P2M'
GROUP BY merchant_id HAVING count(*) >= 30
ORDER BY refund_pct DESC LIMIT 20;

-- @R18
SELECT u.user_id, u.full_name, u.kyc_status, sum(t.amount) AS total_sent
FROM users u
JOIN vpas v ON v.user_id = u.user_id
JOIN transactions t ON t.payer_vpa = v.vpa AND t.status = 'SUCCESS'
WHERE u.kyc_status <> 'VERIFIED'
GROUP BY u.user_id, u.full_name, u.kyc_status
HAVING sum(t.amount) >= 10000 ORDER BY total_sent DESC;

-- @R19
-- Aggregate transaction facts once instead of running two correlated subqueries per merchant.
SELECT m.merchant_id, m.merchant_name, a.last_payment_at,
       coalesce(a.successful_payments, 0) AS successful_payments
FROM merchants m
LEFT JOIN (
    SELECT merchant_id, max(initiated_at) AS last_payment_at,
           count(*) FILTER (WHERE status = 'SUCCESS') AS successful_payments
    FROM transactions WHERE merchant_id IS NOT NULL
    GROUP BY merchant_id
) a ON a.merchant_id = m.merchant_id
WHERE m.is_verified AND m.city_id = 1
ORDER BY successful_payments DESC;

-- @R20
SELECT initiated_at::date AS day, count(*) AS payments,
       round(100.0 * count(*) FILTER (WHERE status = 'SUCCESS') / count(*), 2) AS success_pct
FROM transactions
WHERE initiated_at >= DATE '2026-06-01' AND initiated_at < DATE '2026-07-01'
GROUP BY initiated_at::date ORDER BY day;

-- @R21
SELECT merchant_id, merchant_name, merchant_vpa, city_id
FROM merchants WHERE merchant_name ILIKE '%chai%'
ORDER BY merchant_name LIMIT 25;

-- @R22
SELECT ba.bank_name, ba.account_last4, ba.is_primary, v.vpa, v.is_active
FROM bank_accounts ba LEFT JOIN vpas v ON v.account_id = ba.account_id
WHERE ba.user_id = 15177 ORDER BY ba.is_primary DESC;

-- @R23
-- Benchmark cursor is derived from the same ordered data once; applications pass
-- the last row's (initiated_at, txn_id) from the preceding page as the cursor.
WITH cursor AS MATERIALIZED (
    SELECT initiated_at, txn_id FROM transactions
    ORDER BY initiated_at DESC, txn_id DESC OFFSET 199999 LIMIT 1
)
SELECT t.txn_id, t.upi_ref, t.txn_type, t.amount, t.status, t.initiated_at
FROM transactions t CROSS JOIN cursor c
WHERE (t.initiated_at, t.txn_id) < (c.initiated_at, c.txn_id)
ORDER BY t.initiated_at DESC, t.txn_id DESC LIMIT 25;

-- @R24
SELECT txn_id, payer_vpa, payee_vpa, amount, status, failure_code, initiated_at, completed_at
FROM transactions WHERE upi_ref = '600977648064';

-- @R25
SELECT ba.bank_name,
       round(avg(EXTRACT(EPOCH FROM (t.completed_at - t.initiated_at))), 2) AS avg_seconds,
       count(*) AS payments
FROM transactions t
JOIN vpas v ON v.vpa = t.payer_vpa
JOIN bank_accounts ba ON ba.account_id = v.account_id
WHERE t.completed_at IS NOT NULL AND t.initiated_at >= DATE '2026-06-01'
GROUP BY ba.bank_name ORDER BY avg_seconds DESC;

-- @W01
INSERT INTO transactions (txn_id, upi_ref, txn_type, payer_vpa, payee_vpa, merchant_id,
                          amount, initiated_at, status)
VALUES (90000001, '999900000001', 'P2M', 'aditya.gupta15177@okhdfcbank',
        'balaji2@okbizaxis', 2, 250.00, '2026-07-01 09:00:00+05:30', 'PENDING');

-- @W02
UPDATE transactions SET status = 'SUCCESS',
       completed_at = initiated_at + interval '4 seconds'
WHERE txn_id = (SELECT min(txn_id) FROM transactions WHERE status = 'PENDING');

-- @W03
UPDATE rewards SET status = 'CREDITED', credited_at = '2026-07-01 09:05:00+05:30'
WHERE reward_id = (SELECT min(reward_id) FROM rewards
                   WHERE user_id = 15177 AND status = 'UNSCRATCHED');

-- @W04
UPDATE rewards SET status = 'EXPIRED'
WHERE status = 'UNSCRATCHED' AND expires_at < TIMESTAMPTZ '2026-07-04 00:00:00+05:30';

-- @W05
UPDATE bill_payments SET status = 'OVERDUE'
WHERE status = 'DUE' AND due_date < DATE '2026-07-05';

-- @END
ROLLBACK;
