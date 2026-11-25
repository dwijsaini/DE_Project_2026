-- CP3 indexes selected from docs/03_baseline_timings.md and the raw baseline
-- plans in benchmarks/results/baseline/. Run after loading the gpay schema.
-- These are workload indexes only; do not alter data or server settings here.

-- R01, R03, R14, R18, R22, R25: user-to-VPA filters/joins (user_id first
-- because each query starts from one user's VPAs; vpa also covers the join).
CREATE INDEX idx_vpas_user_id_vpa
    ON gpay.vpas USING btree (user_id, vpa);

-- R01: history by payer or payee, newest first. Separate indexes let the OR
-- predicate use bitmap paths; initiated_at DESC also supplies the sort order.
CREATE INDEX idx_transactions_payer_vpa_initiated_desc
    ON gpay.transactions USING btree (payer_vpa, initiated_at DESC);

CREATE INDEX idx_transactions_payee_vpa_initiated_desc
    ON gpay.transactions USING btree (payee_vpa, initiated_at DESC);

-- R04: pending reconciliation rows in initiation order; the partial predicate
-- keeps successful/terminal rows out of this relatively narrow index.
CREATE INDEX idx_transactions_pending_initiated
    ON gpay.transactions USING btree (initiated_at)
    WHERE status = 'PENDING';

-- R05, R13, R19: merchant/time access. merchant_id leads for per-merchant
-- lookups and the R13 anti-membership check; initiated_at narrows time ranges
-- and supplies R19's last_payment_at maximum.
CREATE INDEX idx_transactions_merchant_initiated
    ON gpay.transactions USING btree (merchant_id, initiated_at DESC)
    WHERE merchant_id IS NOT NULL;

-- R19: repeated successful-count subquery per merchant; merchant_id leads for
-- each correlated lookup and the partial condition keeps this index compact.
CREATE INDEX idx_transactions_success_merchant
    ON gpay.transactions USING btree (merchant_id)
    WHERE status = 'SUCCESS' AND merchant_id IS NOT NULL;

-- R09: the baseline window sort spills 17.8 MB. Match its partition keys and
-- ordering key; only SUCCESS rows are needed by this query.
CREATE INDEX idx_transactions_success_payer_payee_initiated
    ON gpay.transactions USING btree (payer_vpa, payee_vpa, initiated_at)
    WHERE status = 'SUCCESS';

-- R23: newest-first transaction page; the baseline full sort spills to disk.
CREATE INDEX idx_transactions_initiated_desc
    ON gpay.transactions USING btree (initiated_at DESC);

-- W02: the update chooses the smallest txn_id among pending rows. The partial
-- index makes that MIN lookup start at the first pending identifier.
CREATE INDEX idx_transactions_pending_txn_id
    ON gpay.transactions USING btree (txn_id)
    WHERE status = 'PENDING';

-- R10, R11, W03, W04: active unscratched rewards. Expiry-first supports both
-- expiring-reward scans; user_id first narrows R10, and reward_id supports the
-- oldest-card lookup in W03. Partial predicates exclude settled rewards.
CREATE INDEX idx_rewards_unscratched_user_expiry
    ON gpay.rewards USING btree (user_id, expires_at)
    WHERE status = 'UNSCRATCHED';

CREATE INDEX idx_rewards_unscratched_expiry
    ON gpay.rewards USING btree (expires_at)
    WHERE status = 'UNSCRATCHED';

CREATE INDEX idx_rewards_unscratched_user_reward
    ON gpay.rewards USING btree (user_id, reward_id)
    WHERE status = 'UNSCRATCHED';

-- R12, W05: unpaid bill filtering. user_id leads for R12; the W05 partial
-- index uses due_date to find only DUE bills before the cutoff.
CREATE INDEX idx_bills_due_user_date
    ON gpay.bill_payments USING btree (user_id, due_date)
    WHERE status = 'DUE';

CREATE INDEX idx_bills_due_date
    ON gpay.bill_payments USING btree (due_date)
    WHERE status = 'DUE';
