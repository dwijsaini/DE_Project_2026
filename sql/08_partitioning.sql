-- CP4 experiment: build a partitioned analytical copy of gpay.transactions.
-- Run after sql/01_schema.sql, sql/02_load_data.sql, and sql/05_indexes.sql.
-- This does not replace the production-shaped table: rewards and disputes
-- reference transactions(txn_id), while a partitioned table's unique key must
-- include initiated_at. See docs/05_scalability_report.md for the tradeoff.

\set ON_ERROR_STOP on

SET TIME ZONE 'UTC';

DROP TABLE IF EXISTS gpay.transactions_partitioned_cp4 CASCADE;

CREATE TABLE gpay.transactions_partitioned_cp4 (
    txn_id       INTEGER NOT NULL,
    upi_ref      CHAR(12) NOT NULL CHECK (upi_ref ~ '^[0-9]{12}$'),
    txn_type     VARCHAR(3) NOT NULL CHECK (txn_type IN ('P2P', 'P2M')),
    payer_vpa    VARCHAR(255) NOT NULL REFERENCES gpay.vpas(vpa) ON DELETE RESTRICT,
    payee_vpa    VARCHAR(255) NOT NULL,
    merchant_id  INTEGER REFERENCES gpay.merchants(merchant_id) ON DELETE RESTRICT,
    amount       NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    note         TEXT,
    initiated_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    status       VARCHAR(10) NOT NULL
        CHECK (status IN ('SUCCESS', 'FAILED', 'REVERSED', 'REFUNDED', 'PENDING')),
    failure_code VARCHAR(3),
    CONSTRAINT transactions_partitioned_cp4_pk PRIMARY KEY (txn_id, initiated_at),
    CONSTRAINT transactions_partitioned_cp4_upi_ref UNIQUE (upi_ref, initiated_at),
    CHECK (payer_vpa <> payee_vpa),
    CHECK ((txn_type = 'P2P' AND merchant_id IS NULL)
        OR (txn_type = 'P2M' AND merchant_id IS NOT NULL)),
    CHECK ((status = 'FAILED' AND failure_code IS NOT NULL)
        OR (status <> 'FAILED' AND failure_code IS NULL)),
    CHECK ((status = 'PENDING' AND completed_at IS NULL)
        OR (status <> 'PENDING' AND completed_at IS NOT NULL)),
    CHECK (status <> 'REFUNDED' OR txn_type = 'P2M')
) PARTITION BY RANGE (initiated_at);

-- Use Asia/Kolkata month boundaries to match the reporting timezone in the
-- workload. A default partition keeps timestamps outside this range loadable.
DO $partitions$
DECLARE
    month_start DATE := DATE '2025-01-01';
    month_end   DATE;
    child_name  TEXT;
BEGIN
    WHILE month_start < DATE '2027-01-01' LOOP
        month_end := (month_start + INTERVAL '1 month')::DATE;
        child_name := format(
            'transactions_cp4_%s_%s',
            to_char(month_start, 'YYYY'),
            to_char(month_start, 'MM')
        );
        EXECUTE format(
            'CREATE TABLE gpay.%I PARTITION OF gpay.transactions_partitioned_cp4 '
            'FOR VALUES FROM (%L) TO (%L)',
            child_name,
            month_start::TIMESTAMP AT TIME ZONE 'Asia/Kolkata',
            month_end::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'
        );
        month_start := month_end;
    END LOOP;
END
$partitions$;

CREATE TABLE gpay.transactions_cp4_default
    PARTITION OF gpay.transactions_partitioned_cp4 DEFAULT;

CREATE INDEX transactions_partitioned_cp4_payer_time_idx
    ON gpay.transactions_partitioned_cp4 (payer_vpa, initiated_at DESC);
CREATE INDEX transactions_partitioned_cp4_time_idx
    ON gpay.transactions_partitioned_cp4 (initiated_at DESC);

INSERT INTO gpay.transactions_partitioned_cp4 (
    txn_id, upi_ref, txn_type, payer_vpa, payee_vpa, merchant_id, amount,
    note, initiated_at, completed_at, status, failure_code
)
SELECT txn_id, upi_ref, txn_type, payer_vpa, payee_vpa, merchant_id, amount,
       note, initiated_at, completed_at, status, failure_code
FROM gpay.transactions;

ANALYZE gpay.transactions_partitioned_cp4;

-- A month-bounded query should scan only the 2026-06 partition. Preserve this
-- EXPLAIN output in benchmarks/results/large/ when running the CP4 workload.
EXPLAIN (ANALYZE, BUFFERS)
SELECT txn_id, upi_ref, payer_vpa, payee_vpa, amount, status, initiated_at
FROM gpay.transactions_partitioned_cp4
WHERE initiated_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND initiated_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
ORDER BY initiated_at DESC;

-- This all-history aggregate has no partition key filter and must visit every
-- partition; it demonstrates a workload that does not benefit from pruning.
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*)
FROM gpay.transactions_partitioned_cp4
GROUP BY status;
