-- Phase 4/5 workload indexes for the Google Pay database.
-- Safe to rerun. Run after loading data, then run ANALYZE.
SET search_path TO gpay;

-- User-to-VPA lookups and VPA-to-account lookups.
CREATE INDEX IF NOT EXISTS idx_vpas_user_vpa
    ON vpas (user_id, vpa) INCLUDE (account_id, is_active);
CREATE INDEX IF NOT EXISTS idx_vpas_account
    ON vpas (account_id) INCLUDE (vpa, is_active);
CREATE INDEX IF NOT EXISTS idx_bank_accounts_user_primary
    ON bank_accounts (user_id, is_primary DESC)
    INCLUDE (account_id, bank_name, account_last4);

-- Transaction history, user spending, daily payment limits, and bank health.
CREATE INDEX IF NOT EXISTS idx_txn_payer_time
    ON transactions (payer_vpa, initiated_at DESC)
    INCLUDE (txn_id, upi_ref, payee_vpa, amount, status);
CREATE INDEX IF NOT EXISTS idx_txn_payee_time
    ON transactions (payee_vpa, initiated_at DESC)
    INCLUDE (txn_id, upi_ref, payer_vpa, amount, status);
CREATE INDEX IF NOT EXISTS idx_txn_payer_success_time
    ON transactions (payer_vpa, initiated_at)
    INCLUDE (merchant_id, amount) WHERE status = 'SUCCESS';
CREATE INDEX IF NOT EXISTS idx_txn_payer_daily_limit
    ON transactions (payer_vpa, initiated_at)
    INCLUDE (amount, status) WHERE status IN ('SUCCESS', 'PENDING');
CREATE INDEX IF NOT EXISTS idx_txn_pending_time
    ON transactions (initiated_at)
    INCLUDE (txn_id, upi_ref, payer_vpa, amount) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_txn_pending_id
    ON transactions (txn_id) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_txn_merchant_success_time
    ON transactions (merchant_id, initiated_at)
    INCLUDE (amount) WHERE status = 'SUCCESS';
CREATE INDEX IF NOT EXISTS idx_txn_success_time_merchant
    ON transactions (initiated_at, merchant_id)
    INCLUDE (amount) WHERE status = 'SUCCESS';
CREATE INDEX IF NOT EXISTS idx_txn_failed_time
    ON transactions (initiated_at)
    INCLUDE (payer_vpa, failure_code) WHERE status = 'FAILED';
CREATE INDEX IF NOT EXISTS idx_txn_p2p_payee_time
    ON transactions (payee_vpa, initiated_at)
    INCLUDE (payer_vpa, amount) WHERE txn_type = 'P2P' AND status = 'SUCCESS';
CREATE INDEX IF NOT EXISTS idx_txn_success_pair_time
    ON transactions (payer_vpa, payee_vpa, initiated_at)
    INCLUDE (txn_id, amount) WHERE status = 'SUCCESS';
CREATE INDEX IF NOT EXISTS idx_txn_merchant
    ON transactions (merchant_id) WHERE merchant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_txn_p2m_merchant
    ON transactions (merchant_id) INCLUDE (status) WHERE txn_type = 'P2M';
CREATE INDEX IF NOT EXISTS idx_txn_merchant_time_status
    ON transactions (merchant_id, initiated_at) INCLUDE (status)
    WHERE merchant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_txn_time_status
    ON transactions (initiated_at) INCLUDE (status);
CREATE INDEX IF NOT EXISTS idx_txn_completed_time
    ON transactions (initiated_at) INCLUDE (completed_at, payer_vpa)
    WHERE completed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_txn_ops_page
    ON transactions (initiated_at DESC, txn_id DESC)
    INCLUDE (upi_ref, txn_type, amount, status);

-- Reward and bill lookups, notifications, and batch updates.
CREATE INDEX IF NOT EXISTS idx_rewards_user_unscratched_expiry
    ON rewards (user_id, expires_at)
    INCLUDE (reward_id, reward_type, issued_at) WHERE status = 'UNSCRATCHED';
CREATE INDEX IF NOT EXISTS idx_rewards_unscratched_expiry
    ON rewards (expires_at) INCLUDE (reward_id, user_id)
    WHERE status = 'UNSCRATCHED';
CREATE INDEX IF NOT EXISTS idx_rewards_unscratched_user_id
    ON rewards (user_id, reward_id) WHERE status = 'UNSCRATCHED';
CREATE INDEX IF NOT EXISTS idx_bills_due_user_date
    ON bill_payments (user_id, due_date)
    INCLUDE (bill_id, biller_name, amount) WHERE status = 'DUE';
CREATE INDEX IF NOT EXISTS idx_bills_due_date
    ON bill_payments (due_date) WHERE status = 'DUE';

-- Open-dispute SLA checks and merchant name substring searches.
CREATE INDEX IF NOT EXISTS idx_disputes_open_raised
    ON disputes (raised_at) INCLUDE (dispute_id, txn_id, reason)
    WHERE status = 'OPEN';
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_merchants_name_trgm
    ON merchants USING GIN (merchant_name gin_trgm_ops);

ANALYZE;
