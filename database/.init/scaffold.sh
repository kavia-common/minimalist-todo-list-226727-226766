#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/minimalist-todo-list-226727-226766/database"
LOG="$WORKSPACE/setup.log"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"
: >"$LOG"
# If supabase CLI exists, attempt a non-interactive init; otherwise skip gracefully
if [ ! -d "$WORKSPACE/.supabase" ] && [ ! -d "$WORKSPACE/supabase" ]; then
  if command -v supabase >/dev/null 2>&1; then
    # prefer non-interactive flags; tolerate older/newer CLIs via || true and verify artifacts
    if ! supabase init --project-ref minimal-todo --no-browser --skip-analytics >>"$LOG" 2>&1; then
      echo "scaffold-01: supabase init failed; continuing without abort (see $LOG)" >>"$LOG"
    fi
    if [ ! -d "$WORKSPACE/.supabase" ] && [ ! -d "$WORKSPACE/supabase" ]; then
      echo "scaffold-01: supabase init produced no artifacts; continuing" >>"$LOG"
    else
      echo "scaffold-01: supabase init created artifacts" >>"$LOG"
    fi
  else
    echo "scaffold-01: supabase CLI not found; skipping supabase init" >>"$LOG"
  fi
fi
# Schema management: backup existing schema.sql with UTC timestamp, then create minimal schema if missing
SCHEMA="$WORKSPACE/schema.sql"
if [ -f "$SCHEMA" ]; then
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  cp -a "$SCHEMA" "$SCHEMA.bak.$ts" >>"$LOG" 2>&1 || true
  echo "scaffold-01: backed up existing schema to schema.sql.bak.$ts" >>"$LOG"
else
  cat > "$SCHEMA" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS todos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  completed boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now()
);
SQL
  echo "scaffold-01: wrote new schema.sql" >>"$LOG"
fi
# Create .env placeholder only if missing
ENVFILE="$WORKSPACE/.env"
if [ ! -f "$ENVFILE" ]; then
  cat > "$ENVFILE" <<'ENV'
# Local placeholder values; override via container env in real deployments
SUPABASE_URL=http://localhost:54321
SUPABASE_ANON_KEY=anon_key_placeholder
# For direct Postgres access, set PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE
ENV
  echo "scaffold-01: created .env placeholder" >>"$LOG"
else
  echo "scaffold-01: .env already exists; leaving intact" >>"$LOG"
fi
# Minimal validation: ensure psql binary exists (postgres client is preinstalled in image normally)
if ! command -v psql >/dev/null 2>&1; then
  echo "scaffold-01: psql not found in PATH" >>"$LOG"
else
  psql --version >>"$LOG" 2>&1 || true
fi
exit 0
