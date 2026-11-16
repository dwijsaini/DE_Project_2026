# Google Pay database schema design

> **CP1 implementation.** The SQL schema and ER diagram use the same nine tables and relationships. The schema was compared with Rudra's `sql/01_schema.sql`; table and column names, key relationships, nullable seed fields, and `CHAR(4)` MCC representation match. PostgreSQL load and loaded-database integrity results remain pending because PostgreSQL is unavailable in this environment.

## Data model

The model contains the nine supplied relations: `cities`, `users`, `bank_accounts`, `vpas`, `merchants`, `transactions`, `rewards`, `bill_payments`, and `disputes`. The ER picture is in [`diagrams/er_diagram.svg`](../diagrams/er_diagram.svg), with editable Mermaid source in [`diagrams/er_diagram.mmd`](../diagrams/er_diagram.mmd).

All tables belong in the PostgreSQL `gpay` schema. Use the CSV column names exactly because `queries/workload_30.sql` depends on them. Monetary values use `NUMERIC(12,2)`; offset-bearing timestamps use `TIMESTAMPTZ`; dates without a time use `DATE`; flags use `BOOLEAN`. IDs use `INTEGER` for the supplied ranges, except choose a wider type if the team wants headroom for future growth. Preserve identifiers that may contain leading zeroes (phone, last four digits, IFSC, UPI reference, consumer number) as text, not numbers.

## Data dictionary and proposed constraints

`PK` = primary key, `FK` = foreign key. `NN` = not null. Optional values below reflect empty cells found in the seed CSVs.

### `cities` — 10 rows

| Column | Proposed type | Constraint | Why |
|---|---|---|---|
| `city_id` | INTEGER | PK, NN | Stable city identifier. |
| `city_name` | TEXT | NN | Display name. |
| `state` | TEXT | NN | State name. |

FD: `city_id → city_name, state`.

### `users` — 40,000 rows

| Column | Proposed type | Constraint | Why |
|---|---|---|---|
| `user_id` | INTEGER | PK, NN | Stable user identifier. |
| `full_name` | TEXT | NN | User's display/legal name. |
| `phone` | VARCHAR(10) | NN, UNIQUE; digit-format CHECK | Keep as text; it is an identifier, not a quantity. |
| `email` | TEXT | NULL, UNIQUE when present | 15,950 seed rows have no email; PostgreSQL UNIQUE permits multiple NULLs. |
| `city_id` | INTEGER | NN, FK → `cities.city_id`, RESTRICT | City reference; don't duplicate city/state names on the user. |
| `kyc_status` | VARCHAR(10) | NN, CHECK in `VERIFIED`, `PENDING`, `REJECTED` | Observed status domain. |
| `is_blocked` | BOOLEAN | NN | CSV `t`/`f` values are flags. |
| `created_at` | TIMESTAMPTZ | NN | CSV timestamps include offsets. |

FD: `user_id → full_name, phone, email, city_id, kyc_status, is_blocked, created_at`. A non-null email and phone should identify at most one user.

### `bank_accounts` — 53,333 rows

| Column | Proposed type | Constraint | Why |
|---|---|---|---|
| `account_id` | INTEGER | PK, NN | Stable linked-account identifier. |
| `user_id` | INTEGER | NN, FK → `users.user_id`, RESTRICT | Account owner. |
| `bank_name` | TEXT | NN | Bank display name. |
| `ifsc` | CHAR(11) | NN, IFSC-format CHECK | Branch code; not unique because many accounts can use one branch. |
| `account_last4` | CHAR(4) | NN, digit-format CHECK | Preserve leading zeroes and avoid storing full account numbers. |
| `account_type` | VARCHAR(10) | NN, CHECK in `SAVINGS`, `CURRENT` | Observed domain. |
| `is_primary` | BOOLEAN | NN; at most one primary per user | Enforced by a generated nullable `primary_user_id` and UNIQUE constraint; non-primary rows yield NULL, which PostgreSQL allows repeatedly. |
| `linked_at` | TIMESTAMPTZ | NULL | 9 seed rows have no linked timestamp. |

FD: `account_id → user_id, bank_name, ifsc, account_last4, account_type, is_primary, linked_at`.

### `vpas` — 53,333 rows

| Column | Proposed type | Constraint | Why |
|---|---|---|---|
| `vpa` | VARCHAR(255) | PK, NN, VPA-format CHECK | Natural identifier used by the workload joins. |
| `user_id` | INTEGER | NN, FK → `users.user_id`, RESTRICT | VPA owner; retained for direct workload access. |
| `account_id` | INTEGER | NN, FK → `bank_accounts.account_id`, RESTRICT | Linked bank account. |
| `is_active` | BOOLEAN | NN | Whether the VPA can receive payments. |
| `created_at` | TIMESTAMPTZ | NULL | 9 seed rows have no creation timestamp. |

FD: `vpa → user_id, account_id, is_active, created_at`. `vpas.user_id` is redundant because `account_id` already determines the owner through `bank_accounts`; keeping it supports the given queries. Enforce owner agreement with a composite FK to `bank_accounts(account_id,user_id)` if the parent has a matching UNIQUE constraint. CSV profile found no account/user mismatches.

### `merchants` — 3,000 rows

| Column | Proposed type | Constraint | Why |
|---|---|---|---|
| `merchant_id` | INTEGER | PK, NN | Stable merchant identifier. |
| `merchant_name` | TEXT | NN | Search/display name. |
| `mcc` | CHAR(4) | NN, digit CHECK allowing 3 or 4 digits | A category code, not a quantity; the fixed-width type stores any three-digit code with its trailing pad. |
| `merchant_vpa` | VARCHAR(255) | NN, UNIQUE, VPA-format CHECK | Merchant payment address. |
| `city_id` | INTEGER | NN, FK → `cities.city_id`, RESTRICT | Merchant location. |
| `is_verified` | BOOLEAN | NN | Verification flag. |
| `onboarded_on` | DATE | NULL | 7 seed rows have no onboarding date. |

FD: `merchant_id → merchant_name, mcc, merchant_vpa, city_id, is_verified, onboarded_on`; `merchant_vpa` is also a candidate key.

### `transactions` — 250,468 rows

| Column | Proposed type | Constraint | Why |
|---|---|---|---|
| `txn_id` | INTEGER | PK, NN | Stable payment identifier. |
| `upi_ref` | CHAR(12) | NN, UNIQUE, 12-digit CHECK | Payment reference is an identifier; preserve exact width. |
| `txn_type` | VARCHAR(3) | NN, CHECK in `P2P`, `P2M` | Payment kind. |
| `payer_vpa` | VARCHAR(255) | NN, FK → `vpas.vpa`, RESTRICT | Payer is represented by a known VPA. |
| `payee_vpa` | VARCHAR(255) | NN | P2P payees may be on other UPI apps; don't require a `vpas` FK. |
| `merchant_id` | INTEGER | NULL for P2P; FK → `merchants.merchant_id`, RESTRICT for P2M | Merchant context exists only for P2M. |
| `amount` | NUMERIC(12,2) | NN, CHECK `> 0` | Currency amount; decimal arithmetic. |
| `note` | TEXT | NULL | 175,013 rows have an empty note. |
| `initiated_at` | TIMESTAMPTZ | NN | Event timestamp with offset. |
| `completed_at` | TIMESTAMPTZ | NULL only while pending | 125 pending transactions have no completion time. |
| `status` | VARCHAR(10) | NN, CHECK in `SUCCESS`, `FAILED`, `REVERSED`, `REFUNDED`, `PENDING` | Observed lifecycle domain. |
| `failure_code` | VARCHAR(3) | NULL unless failed | 238,077 rows are empty; all 12,391 `FAILED` rows have codes in the seed profile. |

FD: `txn_id → upi_ref, txn_type, payer_vpa, payee_vpa, merchant_id, amount, note, initiated_at, completed_at, status, failure_code`; `upi_ref` is a candidate key. Expected row rules: P2P has no `merchant_id`; P2M has one; `payer_vpa <> payee_vpa`; `FAILED` iff `failure_code` is present; `PENDING` iff `completed_at` is absent; `REFUNDED` is P2M only. Use CHECKs for row-local rules. Cross-table equality of a P2M `payee_vpa` and its merchant's `merchant_vpa` needs an integrity query (or a trigger), not a basic CHECK.

Do not add a foreign key from `payee_vpa` to `vpas`: CSV inspection found 16,583 payment payee addresses that are neither a Google Pay VPA nor a merchant VPA, consistent with P2P users on other apps. For P2M rows, all inspected payee addresses matched their referenced merchant VPA.

### `rewards` — 39,799 rows

| Column | Proposed type | Constraint | Why |
|---|---|---|---|
| `reward_id` | INTEGER | PK, NN | Reward identifier. |
| `user_id` | INTEGER | NN, FK → `users.user_id`, RESTRICT | User shown the reward. |
| `txn_id` | INTEGER | NN, FK → `transactions.txn_id`, RESTRICT | Related transaction. |
| `reward_type` | VARCHAR(20) | NN, CHECK in `SCRATCH_CARD`, `CASHBACK`, `COUPON` | Observed reward domain. |
| `amount` | NUMERIC(12,2) | NN, CHECK `>= 0` | Reward value. |
| `status` | VARCHAR(12) | NN, CHECK in `CREDITED`, `EXPIRED`, `UNSCRATCHED` | Reward lifecycle. |
| `issued_at` | TIMESTAMPTZ | NN | Issue timestamp. |
| `expires_at` | TIMESTAMPTZ | NN, CHECK `>= issued_at` | Expiry timestamp. |
| `credited_at` | TIMESTAMPTZ | NULL unless credited | Empty for 8,054 expired/unscratched rewards. |

FD: `reward_id → user_id, txn_id, reward_type, amount, status, issued_at, expires_at, credited_at`. `user_id` is redundant if it is always the payer of `txn_id`; it is retained for the supplied user-based queries. Verify user/transaction owner agreement before adding any extra enforcement.

### `bill_payments` — 30,000 rows

| Column | Proposed type | Constraint | Why |
|---|---|---|---|
| `bill_id` | INTEGER | PK, NN | Bill payment identifier. |
| `user_id` | INTEGER | NN, FK → `users.user_id`, RESTRICT | Bill owner. |
| `biller_category` | VARCHAR(12) | NN, CHECK in `MOBILE`, `ELECTRICITY`, `DTH`, `GAS`, `BROADBAND`, `WATER`, `FASTAG` | Observed categories. |
| `biller_name` | TEXT | NN | Biller display name. |
| `consumer_number` | VARCHAR(32) | NN | Identifier can have leading zeroes. |
| `amount` | NUMERIC(12,2) | NN, CHECK `> 0` | Bill amount. |
| `due_date` | DATE | NN | Calendar due date. |
| `status` | VARCHAR(8) | NN, CHECK in `PAID`, `DUE`, `OVERDUE` | Observed bill state. |
| `paid_at` | TIMESTAMPTZ | NULL unless paid | Empty for 4,338 due/overdue bills. |

FD: `bill_id → user_id, biller_category, biller_name, consumer_number, amount, due_date, status, paid_at`.

### `disputes` — 3,569 rows

| Column | Proposed type | Constraint | Why |
|---|---|---|---|
| `dispute_id` | INTEGER | PK, NN | Dispute identifier. |
| `txn_id` | INTEGER | NN, FK → `transactions.txn_id`, RESTRICT | Disputed payment. Do not assume one dispute per transaction unless verified. |
| `raised_by` | INTEGER | NN, FK → `users.user_id`, RESTRICT | User who opened the case. |
| `reason` | VARCHAR(32) | NN, CHECK in `MONEY_DEBITED_NOT_CREDITED`, `WRONG_PAYEE`, `MERCHANT_NOT_DELIVERED`, `DUPLICATE_PAYMENT`, `FRAUD` | Observed reason domain. |
| `raised_at` | TIMESTAMPTZ | NN | Case creation time. |
| `status` | VARCHAR(10) | NN, CHECK in `OPEN`, `RESOLVED`, `REJECTED` | Case state. |
| `resolved_at` | TIMESTAMPTZ | NULL for open disputes | 116 open cases have no resolution time. |

FD: `dispute_id → txn_id, raised_by, reason, raised_at, status, resolved_at`. A row CHECK can require `resolved_at IS NULL` for `OPEN` and non-NULL otherwise.

## Relationships and delete behavior

| Parent → child | Cardinality | Delete behavior |
|---|---|---|
| `cities` → `users` | one city to many users | RESTRICT: retain the referenced city. |
| `cities` → `merchants` | one city to many merchants | RESTRICT. |
| `users` → `bank_accounts` | one user to many linked accounts | RESTRICT to preserve payment history. |
| `users` → `vpas` | one user to many VPAs | RESTRICT. |
| `bank_accounts` → `vpas` | one account to zero or more VPAs; seed has equal row counts and each account is linked once | RESTRICT; do not infer a one-to-one rule from equal totals alone. |
| `vpas` → `transactions` as payer | one VPA to many transactions | RESTRICT to preserve payment history. |
| `merchants` → `transactions` | one merchant to many P2M transactions | RESTRICT. |
| `users` → `rewards` and `transactions` → `rewards` | one user/transaction to many rewards | RESTRICT; retain financial records. |
| `users` → `bill_payments` | one user to many bills | RESTRICT. |
| `transactions` → `disputes` | one transaction to zero or many disputes | RESTRICT. |
| `users` → `disputes` as raiser | one user to many disputes | RESTRICT. |

`transactions.payee_vpa` is intentionally polymorphic text: a P2P destination can be external. It is not drawn as an FK. P2M `merchant_id` supplies the relational merchant link.

## Normal forms and deliberate redundancy

All columns are atomic, so every relation is in 1NF. Each relation has a single-column identifier key (VPA itself is the natural key for `vpas`); under the FDs listed above, there are no partial dependencies, so the relations are in 2NF. Non-key descriptive attributes are kept with their entity, rather than copied into child relations, so each relation is in 3NF and BCNF under the stated dependencies.

Three cross-table redundancies are intentional because the fixed workload and seed format require them:

1. `vpas.user_id` can be derived by joining `vpas.account_id` to `bank_accounts.account_id`. It supports direct VPA-to-user lookups in the provided queries. Enforce same-owner consistency with a composite FK where feasible.
2. For P2M, `transactions.payee_vpa` duplicates the merchant's `merchant_vpa`. It remains because transaction history queries read the payee VPA and workload SQL must not be edited. Validate that they match for all P2M rows.
3. `rewards.user_id` may be derived from the payer VPA of `rewards.txn_id`. It supports user reward queries. Check that the reward owner matches the transaction payer's user.

For `bank_accounts`, this design treats the supplied `bank_name` as an account attribute. If the team treats `ifsc → bank_name` as a required business dependency, a separate branch lookup would remove that possible transitive dependency; the input and workload do not provide a branch master table, so the proposed schema retains both source columns.

The transaction status does not determine a specific failure code; it only determines whether a failure code is required. `merchant_id` and `payee_vpa` are not interchangeable because P2P may target an external VPA.

## Seed-file profile and integrity checks

The CSV files contain the expected row counts listed in `README.md`. Inspection of empty fields found: users.email 15,950; bank_accounts.linked_at 9; vpas.created_at 9; merchants.onboarded_on 7; transactions.merchant_id 110,581, note 175,013, completed_at 125, failure_code 238,077; rewards.credited_at 8,054; bill_payments.paid_at 4,338; disputes.resolved_at 116. These are consistent with optional email/note and dates, P2P transactions, pending transactions, non-failed payments, uncredited rewards, unpaid bills and open disputes. Do not treat these as errors.

CSV-level checks performed before the PostgreSQL load:

| Check | Result from seed-file inspection |
|---|---:|
| Duplicate primary-key values in any of the nine files | 0 |
| User or merchant rows whose `city_id` is absent | 0 |
| Bank-account/VPA user or account references that are absent | 0 |
| Transaction payer VPAs absent from `vpas` | 0 |
| P2P transactions with a non-NULL `merchant_id` | 0 |
| P2M `merchant_id` to `payee_vpa` mismatches | 0 |
| Rewards, bills or disputes with missing user/transaction references | 0 |
| Transaction payee VPA not found among Google Pay VPAs or merchant VPAs | 16,583; expected external P2P destinations, so no payee FK |

**PostgreSQL load evidence: pending.** This environment has no `psql` client or PostgreSQL server, so the DDL and loader could not be executed here. After `sql/01_schema.sql` and `sql/02_load_data.sql` run successfully, record the nine `COUNT(*)` results and at least three SQL integrity-check outputs from the loaded `gpay` schema below. CSV-level checks do not replace database-load results.

```sql
SELECT 'cities' AS table_name, count(*) FROM gpay.cities
UNION ALL SELECT 'users', count(*) FROM gpay.users
UNION ALL SELECT 'bank_accounts', count(*) FROM gpay.bank_accounts
UNION ALL SELECT 'vpas', count(*) FROM gpay.vpas
UNION ALL SELECT 'merchants', count(*) FROM gpay.merchants
UNION ALL SELECT 'transactions', count(*) FROM gpay.transactions
UNION ALL SELECT 'rewards', count(*) FROM gpay.rewards
UNION ALL SELECT 'bill_payments', count(*) FROM gpay.bill_payments
UNION ALL SELECT 'disputes', count(*) FROM gpay.disputes;
```

Recommended loaded-database integrity checks to paste with results:

```sql
-- Every P2M transaction's payee must be the referenced merchant's VPA.
SELECT count(*) AS mismatches
FROM gpay.transactions t
JOIN gpay.merchants m ON m.merchant_id = t.merchant_id
WHERE t.txn_type = 'P2M' AND t.payee_vpa <> m.merchant_vpa;

-- A VPA and its linked bank account must identify the same user.
SELECT count(*) AS mismatches
FROM gpay.vpas v
JOIN gpay.bank_accounts ba ON ba.account_id = v.account_id
WHERE v.user_id <> ba.user_id;

-- Every user should have exactly one primary account in this seed.
SELECT count(*) AS users_with_multiple_primary_accounts
FROM (
  SELECT user_id FROM gpay.bank_accounts
  WHERE is_primary GROUP BY user_id HAVING count(*) > 1
) s;

SELECT count(*) AS users_without_primary_account
FROM gpay.users u
WHERE NOT EXISTS (
  SELECT 1 FROM gpay.bank_accounts ba
  WHERE ba.user_id = u.user_id AND ba.is_primary
);

-- Reward owner should match the user who paid the linked transaction.
SELECT count(*) AS mismatches
FROM gpay.rewards r
JOIN gpay.transactions t ON t.txn_id = r.txn_id
JOIN gpay.vpas v ON v.vpa = t.payer_vpa
WHERE r.user_id <> v.user_id;
```
