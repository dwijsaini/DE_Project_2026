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

-- Confirm the loaded row counts against the seed-file totals in README.md.
SELECT 'cities' AS table_name, count(*) AS loaded_rows FROM gpay.cities
UNION ALL SELECT 'users', count(*) FROM gpay.users
UNION ALL SELECT 'bank_accounts', count(*) FROM gpay.bank_accounts
UNION ALL SELECT 'vpas', count(*) FROM gpay.vpas
UNION ALL SELECT 'merchants', count(*) FROM gpay.merchants
UNION ALL SELECT 'transactions', count(*) FROM gpay.transactions
UNION ALL SELECT 'rewards', count(*) FROM gpay.rewards
UNION ALL SELECT 'bill_payments', count(*) FROM gpay.bill_payments
UNION ALL SELECT 'disputes', count(*) FROM gpay.disputes
ORDER BY table_name;
