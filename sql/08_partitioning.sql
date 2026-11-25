-- Phase 5 partitioning design for transactions.
-- Partition by initiation month because most time-bounded reports filter this column.
-- The partition key is included in PK/UNIQUE constraints as PostgreSQL requires.
SET search_path TO gpay;

CREATE TABLE gpay.transactions_partitioned (
    txn_id INTEGER NOT NULL,
    upi_ref CHAR(12) NOT NULL CHECK (upi_ref ~ '^[0-9]{12}$'),
    txn_type VARCHAR(3) NOT NULL CHECK (txn_type IN ('P2P', 'P2M')),
    payer_vpa VARCHAR(255) NOT NULL REFERENCES gpay.vpas(vpa) ON DELETE RESTRICT,
    payee_vpa VARCHAR(255) NOT NULL,
    merchant_id INTEGER REFERENCES gpay.merchants(merchant_id) ON DELETE RESTRICT,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    note TEXT,
    initiated_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    status VARCHAR(10) NOT NULL
        CHECK (status IN ('SUCCESS', 'FAILED', 'REVERSED', 'REFUNDED', 'PENDING')),
    failure_code VARCHAR(3),
    PRIMARY KEY (txn_id, initiated_at),
    UNIQUE (upi_ref, initiated_at),
    CHECK (payer_vpa <> payee_vpa),
    CHECK ((txn_type = 'P2P' AND merchant_id IS NULL)
        OR (txn_type = 'P2M' AND merchant_id IS NOT NULL)),
    CHECK ((status = 'FAILED' AND failure_code IS NOT NULL)
        OR (status <> 'FAILED' AND failure_code IS NULL)),
    CHECK ((status = 'PENDING' AND completed_at IS NULL)
        OR (status <> 'PENDING' AND completed_at IS NOT NULL)),
    CHECK (status <> 'REFUNDED' OR txn_type = 'P2M')
) PARTITION BY RANGE (initiated_at);

-- Monthly partitions cover the supplied large dataset (Jan 2025–Jun 2026).
-- The DEFAULT partition safely accepts late or future periods until a new month is added.
DO $partition_months$
DECLARE
    month_start DATE := DATE '2025-01-01';
    next_month DATE;
    partition_name TEXT;
BEGIN
    WHILE month_start <= DATE '2026-06-01' LOOP
        next_month := (month_start + INTERVAL '1 month')::DATE;
        partition_name := 'transactions_p' || to_char(month_start, 'YYYY_MM');
        EXECUTE format(
            'CREATE TABLE gpay.%I PARTITION OF gpay.transactions_partitioned FOR VALUES FROM (%L) TO (%L)',
            partition_name, month_start, next_month
        );
        month_start := next_month;
    END LOOP;
END
$partition_months$;

CREATE TABLE gpay.transactions_p_default
    PARTITION OF gpay.transactions_partitioned DEFAULT;

-- To demonstrate pruning with real rows, copy the source table into this design,
-- then EXPLAIN a query with an initiated_at range. The report records the tested plan.
-- INSERT INTO gpay.transactions_partitioned SELECT * FROM gpay.transactions;
-- ANALYZE gpay.transactions_partitioned;
