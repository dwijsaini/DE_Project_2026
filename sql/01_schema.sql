-- Google Pay / UPI schema for PostgreSQL 15+
-- Constraint-only phase: no workload-tuning indexes are created here.
CREATE SCHEMA IF NOT EXISTS gpay;
SET search_path TO gpay;

CREATE TABLE cities (
    city_id INTEGER PRIMARY KEY,
    city_name TEXT NOT NULL,
    state TEXT NOT NULL
);

CREATE TABLE users (
    user_id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL,
    phone VARCHAR(10) NOT NULL UNIQUE
        CHECK (phone ~ '^[0-9]{10}$'),
    email TEXT UNIQUE,
    city_id INTEGER NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    kyc_status VARCHAR(10) NOT NULL
        CHECK (kyc_status IN ('VERIFIED', 'PENDING', 'REJECTED')),
    is_blocked BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE bank_accounts (
    account_id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    bank_name TEXT NOT NULL,
    ifsc CHAR(11) NOT NULL CHECK (rtrim(ifsc) ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
    account_last4 CHAR(4) NOT NULL CHECK (rtrim(account_last4) ~ '^[0-9]{4}$'),
    account_type VARCHAR(10) NOT NULL CHECK (account_type IN ('SAVINGS', 'CURRENT')),
    is_primary BOOLEAN NOT NULL,
    linked_at TIMESTAMPTZ,
    primary_user_id INTEGER GENERATED ALWAYS AS
        (CASE WHEN is_primary THEN user_id END) STORED,
    UNIQUE (account_id, user_id),
    UNIQUE (primary_user_id)
);

CREATE TABLE vpas (
    vpa VARCHAR(255) PRIMARY KEY
        CHECK (vpa ~ '^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+$'),
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    account_id INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ,
    FOREIGN KEY (account_id, user_id)
        REFERENCES bank_accounts(account_id, user_id) ON DELETE RESTRICT
);

CREATE TABLE merchants (
    merchant_id INTEGER PRIMARY KEY,
    merchant_name TEXT NOT NULL,
    mcc CHAR(4) NOT NULL CHECK (rtrim(mcc) ~ '^[0-9]{3,4}$'),
    merchant_vpa VARCHAR(255) NOT NULL UNIQUE
        CHECK (merchant_vpa ~ '^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+$'),
    city_id INTEGER NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    is_verified BOOLEAN NOT NULL,
    onboarded_on DATE
);

CREATE TABLE transactions (
    txn_id INTEGER PRIMARY KEY,
    upi_ref CHAR(12) NOT NULL UNIQUE CHECK (upi_ref ~ '^[0-9]{12}$'),
    txn_type VARCHAR(3) NOT NULL CHECK (txn_type IN ('P2P', 'P2M')),
    payer_vpa VARCHAR(255) NOT NULL REFERENCES vpas(vpa) ON DELETE RESTRICT,
    payee_vpa VARCHAR(255) NOT NULL,
    merchant_id INTEGER REFERENCES merchants(merchant_id) ON DELETE RESTRICT,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    note TEXT,
    initiated_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    status VARCHAR(10) NOT NULL
        CHECK (status IN ('SUCCESS', 'FAILED', 'REVERSED', 'REFUNDED', 'PENDING')),
    failure_code VARCHAR(3),
    CHECK (payer_vpa <> payee_vpa),
    CHECK ((txn_type = 'P2P' AND merchant_id IS NULL)
        OR (txn_type = 'P2M' AND merchant_id IS NOT NULL)),
    CHECK ((status = 'FAILED' AND failure_code IS NOT NULL)
        OR (status <> 'FAILED' AND failure_code IS NULL)),
    CHECK ((status = 'PENDING' AND completed_at IS NULL)
        OR (status <> 'PENDING' AND completed_at IS NOT NULL)),
    CHECK (status <> 'REFUNDED' OR txn_type = 'P2M')
);

CREATE TABLE rewards (
    reward_id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    txn_id INTEGER NOT NULL REFERENCES transactions(txn_id) ON DELETE RESTRICT,
    reward_type VARCHAR(20) NOT NULL
        CHECK (reward_type IN ('SCRATCH_CARD', 'CASHBACK', 'COUPON')),
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    status VARCHAR(12) NOT NULL CHECK (status IN ('CREDITED', 'EXPIRED', 'UNSCRATCHED')),
    issued_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL CHECK (expires_at >= issued_at),
    credited_at TIMESTAMPTZ,
    CHECK ((status = 'CREDITED' AND credited_at IS NOT NULL)
        OR (status <> 'CREDITED' AND credited_at IS NULL))
);

CREATE TABLE bill_payments (
    bill_id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    biller_category VARCHAR(12) NOT NULL CHECK (biller_category IN
        ('MOBILE', 'ELECTRICITY', 'DTH', 'GAS', 'BROADBAND', 'WATER', 'FASTAG')),
    biller_name TEXT NOT NULL,
    consumer_number VARCHAR(32) NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    due_date DATE NOT NULL,
    status VARCHAR(8) NOT NULL CHECK (status IN ('PAID', 'DUE', 'OVERDUE')),
    paid_at TIMESTAMPTZ,
    CHECK ((status = 'PAID' AND paid_at IS NOT NULL)
        OR (status <> 'PAID' AND paid_at IS NULL))
);

CREATE TABLE disputes (
    dispute_id INTEGER PRIMARY KEY,
    txn_id INTEGER NOT NULL REFERENCES transactions(txn_id) ON DELETE RESTRICT,
    raised_by INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    reason VARCHAR(32) NOT NULL CHECK (reason IN
        ('MONEY_DEBITED_NOT_CREDITED', 'WRONG_PAYEE', 'MERCHANT_NOT_DELIVERED',
         'DUPLICATE_PAYMENT', 'FRAUD')),
    raised_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(10) NOT NULL CHECK (status IN ('OPEN', 'RESOLVED', 'REJECTED')),
    resolved_at TIMESTAMPTZ,
    CHECK ((status = 'OPEN' AND resolved_at IS NULL)
        OR (status <> 'OPEN' AND resolved_at IS NOT NULL))
);
