-- Run from the repository root after unzipping seed_data.zip.
-- Example: psql -d <database> -f sql/01_schema.sql -f sql/02_load_data.sql
SET search_path TO gpay;

\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true)
\copy bank_accounts FROM 'seed_data/bank_accounts.csv' WITH (FORMAT csv, HEADER true)
\copy vpas FROM 'seed_data/vpas.csv' WITH (FORMAT csv, HEADER true)
\copy merchants FROM 'seed_data/merchants.csv' WITH (FORMAT csv, HEADER true)
\copy transactions FROM 'seed_data/transactions.csv' WITH (FORMAT csv, HEADER true)
\copy rewards FROM 'seed_data/rewards.csv' WITH (FORMAT csv, HEADER true)
\copy bill_payments FROM 'seed_data/bill_payments.csv' WITH (FORMAT csv, HEADER true)
\copy disputes FROM 'seed_data/disputes.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;

-- Row counts and integrity checks required by CP1 are documented in
-- docs/02_schema_design.md after running this script against PostgreSQL.
