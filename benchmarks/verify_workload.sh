#!/usr/bin/env bash
# =====================================================================
# Google Pay (UPI) DBMS Project: Workload Verification & Equivalence Suite
#
# Validates:
#   1. Semantic equivalence of all rewritten queries (R01, R03, R14, R20, R22)
#      via bidirectional EXCEPT ALL assertions defined in sql/07_verify_equivalence.sql.
#   2. Bidirectional NULL-safety correctness of R13 (450 inactive merchants)
#      against the intended relational anti-join.
#   3. Error-free execution and row-count retrieval of all 25 read queries in
#      sql/06_optimized_queries.sql.
#   4. Safe transactional rollback of all 5 write queries (W01–W05) with
#      verification that table row counts are strictly unchanged.
#
# Usage: ./benchmarks/verify_workload.sh [database_name]
# Example: ./benchmarks/verify_workload.sh gpay_cp3
# =====================================================================
set -euo pipefail

DB="${1:-gpay_cp3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKLOAD_ORIG="$ROOT/queries/workload_30.sql"
WORKLOAD_OPT="$ROOT/sql/06_optimized_queries.sql"
EQUIV_SQL="$ROOT/sql/07_verify_equivalence.sql"

echo "====================================================================="
echo "Google Pay Workload Verification Suite"
echo "Database: $DB"
echo "Time:     $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "====================================================================="

# Step 1: Tool & Environment Pre-flight Checks
if ! command -v psql >/dev/null 2>&1; then
  echo "ERROR: psql client not found in PATH." >&2
  exit 1
fi

if ! psql -d "$DB" -X -q -t -c "SELECT 1;" >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to database '$DB'. Please verify PostgreSQL is running." >&2
  exit 1
fi

if [[ ! -f "$EQUIV_SQL" ]]; then
  echo "ERROR: Equivalence SQL file not found at $EQUIV_SQL" >&2
  exit 1
fi

if [[ ! -f "$WORKLOAD_OPT" ]]; then
  echo "ERROR: Optimized workload file not found at $WORKLOAD_OPT" >&2
  exit 1
fi

schema_check="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM information_schema.schemata WHERE schema_name = 'gpay';" | tr -d ' ')"
if [[ "$schema_check" -ne 1 ]]; then
  echo "ERROR: Schema 'gpay' does not exist in database '$DB'." >&2
  exit 1
fi

# Step 2: Record Pre-Verification Row Count Baseline
echo "Verifying initial database state..."
pre_txns="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM gpay.transactions;" | tr -d ' ')"
pre_rewards="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM gpay.rewards;" | tr -d ' ')"
pre_bills="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM gpay.bill_payments;" | tr -d ' ')"
echo "Baseline row counts: transactions=$pre_txns, rewards=$pre_rewards, bills=$pre_bills"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

fail() {
  echo "  [FAIL] $1"
  FAILED_TESTS=$((FAILED_TESTS + 1))
}

pass() {
  echo "  [PASS] $1"
  PASSED_TESTS=$((PASSED_TESTS + 1))
}

# ---------------------------------------------------------------------
# Phase 1: Two-Way Semantic Equivalence Checks via sql/07_verify_equivalence.sql
# ---------------------------------------------------------------------
echo ""
echo "--- Phase 1: Bidirectional Semantic Equivalence Assertions (sql/07_verify_equivalence.sql) ---"

# Execute sql/07_verify_equivalence.sql as the single source of truth
if ! equiv_output="$(psql -d "$DB" -X -q -A -t -v ON_ERROR_STOP=1 -f "$EQUIV_SQL" 2>&1)"; then
  echo "ERROR: Failed executing $EQUIV_SQL against $DB:" >&2
  echo "$equiv_output" >&2
  exit 1
fi

while IFS='|' read -r col1 col2 col3 col4 col5 col6; do
  [[ -z "$col1" ]] && continue
  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  if [[ "$col1" == "R13" ]]; then
    # R13 schema: query_id|buggy_orig_count|intended_orig_count|opt_count|orig_except_opt|opt_except_orig
    buggy_cnt="$col2"
    intended_cnt="$col3"
    opt_cnt="$col4"
    orig_except_opt="$col5"
    opt_except_orig="$col6"

    if [[ "$buggy_cnt" -eq 0 && "$opt_cnt" -gt 0 && "$orig_except_opt" -eq 0 && "$opt_except_orig" -eq 0 ]]; then
      pass "R13 (NOT EXISTS fix): corrected 0 -> $opt_cnt inactive merchants; bidirectional 0 diffs against intended anti-join"
    else
      fail "R13 (NOT EXISTS fix): unexpected results (buggy=$buggy_cnt, intended=$intended_cnt, opt=$opt_cnt, orig_except_opt=$orig_except_opt, opt_except_orig=$opt_except_orig)"
    fi
  else
    # Standard schema: query_id|orig_count|opt_count|orig_except_opt|opt_except_orig
    qid="$col1"
    orig_cnt="$col2"
    opt_cnt="$col3"
    orig_except_opt="$col4"
    opt_except_orig="$col5"

    if [[ "$orig_except_opt" -eq 0 && "$opt_except_orig" -eq 0 ]]; then
      pass "$qid: bidirectional 0 row differences (orig=$orig_cnt, opt=$opt_cnt)"
    else
      fail "$qid: row discrepancies detected (orig_except_opt=$orig_except_opt, opt_except_orig=$opt_except_orig)"
    fi
  fi
done <<< "$equiv_output"

# ---------------------------------------------------------------------
# Phase 2: Execution Integrity of All 25 Read Queries
# ---------------------------------------------------------------------
echo ""
echo "--- Phase 2: Execution Integrity of All 25 Read Queries (R01-R25) ---"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

awk -v dir="$TMP" '
  /^-- @/ { id = ""; if ($2 ~ /^@[RW][0-9]+$/) { id = substr($2, 2); file = dir "/" id ".sql"; printf "" > file }; next }
  id != "" && !/^--/ { print >> file }
' "$WORKLOAD_OPT"

for qfile in $(ls "$TMP"/R*.sql | sort -V); do
  qid="$(basename "$qfile" .sql)"
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  # Strip trailing comments, semicolons, and whitespace so it can be cleanly wrapped in a subquery
  qsql="$(sed -e '/^[[:space:]]*--/d' "$qfile" | tr '\n' ' ' | sed -e 's/[[:space:]]*;[[:space:]]*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if row_count="$(psql -d "$DB" -X -q -A -t -c "SET search_path TO gpay; SELECT count(*) FROM ($qsql) sub;" 2>/dev/null)"; then
    pass "Query $qid executed successfully (returned $row_count rows)"
  else
    err_msg="$(psql -d "$DB" -X -q -c "SET search_path TO gpay; SELECT count(*) FROM ($qsql) sub;" 2>&1 || true)"
    fail "Query $qid failed during execution: $err_msg"
  fi
done

# ---------------------------------------------------------------------
# Phase 3: Transactional Rollback Safety of All 5 Write Queries
# ---------------------------------------------------------------------
echo ""
echo "--- Phase 3: Transactional Rollback Safety for Write Queries (W01-W05) ---"

for wfile in $(ls "$TMP"/W*.sql | sort -V); do
  wid="$(basename "$wfile" .sql)"
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  wsql="$(cat "$wfile")"
  
  # Execute write query inside strict transaction block with immediate ROLLBACK
  if ! psql -d "$DB" -X -q -v ON_ERROR_STOP=1 <<EOF >/dev/null 2>&1
SET search_path TO gpay;
BEGIN;
$wsql
ROLLBACK;
EOF
  then
    fail "Write Query $wid failed during execution inside transaction"
    continue
  fi

  # Verify row counts immediately after rollback
  curr_txns="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM gpay.transactions;" | tr -d ' ')"
  curr_rewards="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM gpay.rewards;" | tr -d ' ')"
  curr_bills="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM gpay.bill_payments;" | tr -d ' ')"

  if [[ "$curr_txns" == "$pre_txns" && "$curr_rewards" == "$pre_rewards" && "$curr_bills" == "$pre_bills" ]]; then
    pass "Write Query $wid: executed inside transaction and rolled back safely (table state unchanged)"
  else
    fail "Write Query $wid: state leak detected after rollback! Counts differed: txns=$curr_txns vs $pre_txns"
  fi
done

# ---------------------------------------------------------------------
# Final Integrity & Summary Check
# ---------------------------------------------------------------------
echo ""
echo "====================================================================="
echo "Final Integrity Verification:"
post_txns="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM gpay.transactions;" | tr -d ' ')"
post_rewards="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM gpay.rewards;" | tr -d ' ')"
post_bills="$(psql -d "$DB" -X -q -t -c "SELECT count(*) FROM gpay.bill_payments;" | tr -d ' ')"

if [[ "$post_txns" == "$pre_txns" && "$post_rewards" == "$pre_rewards" && "$post_bills" == "$pre_bills" ]]; then
  echo "Data Integrity: STRICTLY PRESERVED (0 rows modified across all tables)"
else
  echo "CRITICAL WARNING: Database state modification detected!"
  exit 2
fi

echo "Results: $PASSED_TESTS / $TOTAL_TESTS tests passed ($FAILED_TESTS failures)"
echo "====================================================================="

if [[ "$FAILED_TESTS" -gt 0 ]]; then
  exit 1
fi

exit 0
