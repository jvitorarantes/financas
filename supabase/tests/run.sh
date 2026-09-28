#!/usr/bin/env bash
# Roda as migrations e os testes do banco num PostgreSQL local.
# Uso: supabase/tests/run.sh   (precisa de psql e de um PostgreSQL 15+)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
DB="${TEST_DB:-meu_financeiro_test}"
PSQL=(psql -v ON_ERROR_STOP=1 -q -X)
[ -n "${PGUSER:-}" ] || export PGUSER=postgres

"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
"${PSQL[@]}" -d "$DB" -f "$DIR/supabase_stub.sql" >/dev/null
for f in "$DIR"/../migrations/*.sql; do
  "${PSQL[@]}" -d "$DB" -f "$f" >/dev/null
done
status=0
for t in "$DIR"/test_*.sql; do
  if out=$("${PSQL[@]}" -d "$DB" -f "$t" 2>&1); then
    echo "ok   $(basename "$t")"
  else
    echo "FAIL $(basename "$t")"; echo "$out"; status=1
  fi
done
exit $status
