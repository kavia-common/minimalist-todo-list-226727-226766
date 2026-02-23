#!/usr/bin/env bash
set -euo pipefail
# validation: apply schema.sql, verify 'todos', run healthcheck, optional supabase start
WORKSPACE="/home/kavia/workspace/code-generation/minimalist-todo-list-226727-226766/database"
cd "$WORKSPACE"
LOG="$WORKSPACE/setup.log"
# controlled env loader
if [ -f .env ]; then
  while IFS='=' read -r key val; do
    key=$(echo "$key" | sed 's/[^A-Za-z0-9_]*//g')
    [ -z "$key" ] && continue
    val=$(echo "$val" | sed -E 's/^\s*"(.*)"\s*$/\1/; s/^\s*'"'"'(.*)'"'"'\s*$/\1/')
    case "$val" in *\$*|*`*|*\(*|*\)*) val="";; esac
    export "$key"="$val"
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env || true)
fi
# apply schema if psql present
if command -v psql >/dev/null 2>&1; then
  PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}" PGPASS="${PGPASSWORD:-}" PGDB="${PGDATABASE:-postgres}"
  PSQL_CONN="postgresql://$PGUSER@$PGHOST:$PGPORT/$PGDB"
  if [ -f schema.sql ]; then
    if ! PGPASSWORD="$PGPASS" psql "$PSQL_CONN" -f schema.sql >>"$LOG" 2>&1; then
      echo "validation-01: ERROR applying schema (see $LOG)" | tee -a "$LOG" >&2
      exit 8
    fi
    # verify table exists using normalized output
    EXISTS=$(PGPASSWORD="$PGPASS" psql "$PSQL_CONN" -tA -c "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='todos');" 2>>"$LOG" | tr -d '\r\n' || true)
    case "$EXISTS" in
      t|true|1) ;;
      *) echo "validation-01: ERROR: todos table not found (exists=$EXISTS)" | tee -a "$LOG" >&2; exit 9; ;;
    esac
  else
    echo "validation-01: schema.sql not found; skipping apply" | tee -a "$LOG"
  fi
else
  echo "validation-01: psql not available; skipping schema apply" | tee -a "$LOG"
fi
# run healthcheck
if [ -x ./healthcheck.sh ]; then
  if ! ./healthcheck.sh 2>&1 | tee -a "$LOG"; then
    echo "validation-01: healthcheck failed" | tee -a "$LOG" >&2
    exit 10
  fi
else
  echo "validation-01: healthcheck.sh missing or not executable" | tee -a "$LOG" >&2
  exit 11
fi
# optional supabase start (gated)
SKIP_SUPABASE_START="${SKIP_SUPABASE_START:-true}"
if [ "$SKIP_SUPABASE_START" = "false" ]; then
  if command -v supabase >/dev/null 2>&1; then
    if command -v docker >/dev/null 2>&1; then
      echo "validation-01: attempting supabase start (this requires Docker access)" | tee -a "$LOG"
      if ! supabase start --project-ref minimal-todo --non-interactive >>"$LOG" 2>&1; then
        echo "validation-01: supabase start failed or is unsupported (see $LOG)" | tee -a "$LOG"
      fi
      supabase stop --project-ref minimal-todo >>"$LOG" 2>&1 || true
    else
      echo "validation-01: docker not available; skipping supabase start" | tee -a "$LOG"
    fi
  else
    echo "validation-01: supabase CLI not available; cannot start services" | tee -a "$LOG"
  fi
else
  echo "validation-01: skipping supabase start (default)" | tee -a "$LOG"
fi
echo "validation-01: completed" | tee -a "$LOG"
