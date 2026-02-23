#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) testing-01: $*" | tee -a "$LOG"; }
# controlled .env parser: KEY=VALUE, strip quotes, ignore suspicious chars
if [ -f .env ]; then
  while IFS='=' read -r key val; do
    key=$(echo "$key" | sed 's/[^A-Za-z0-9_]*//g')
    [ -z "$key" ] && continue
    # strip surrounding quotes
    val=$(echo "$val" | sed -E 's/^\s*"(.*)"\s*$/\1/; s/^\s*\'(.*)\'\s*$/\1/')
    case "$val" in *\$*|*`*|*\(*|*\)*) val="";; esac
    export "$key"="$val"
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env || true)
fi
SU_URL="${SUPABASE_URL:-}"; SU_KEY="${SUPABASE_ANON_KEY:-}"
[ -z "$SU_URL" ] && log "WARN: SUPABASE_URL not set"
[ -z "$SU_KEY" ] && log "WARN: SUPABASE_ANON_KEY not set"
HTTP_OK=1; PSQL_OK=1
# HTTP probe with timeout and small retries
if [ -n "$SU_URL" ]; then
  for i in 1 2 3; do
    if curl -fsS --connect-timeout 3 --max-time 8 "$SU_URL/rest/v1" -H "apikey: $SU_KEY" -o /dev/null 2>/dev/null; then HTTP_OK=0; log "HTTP OK"; break; fi
    sleep 1
  done
  if [ $HTTP_OK -ne 0 ]; then
    # try root
    if curl -fsS --connect-timeout 3 --max-time 8 "$SU_URL" -o /dev/null 2>/dev/null; then HTTP_OK=0; log "HTTP OK (root)"; fi
  fi
fi
# psql probe
if command -v psql >/dev/null 2>&1; then
  PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}" PGPASS="${PGPASSWORD:-}" PGDB="${PGDATABASE:-postgres}"
  PSQL_CONN="postgresql://$PGUSER@$PGHOST:$PGPORT/$PGDB"
  if PGPASSWORD="$PGPASS" psql "$PSQL_CONN" -tA -c '\\conninfo' >/dev/null 2>&1; then PSQL_OK=0; log "PSQL OK"; else log "PSQL UNREACHABLE ($PSQL_CONN)"; fi
fi
if [ $HTTP_OK -ne 0 ] && [ $PSQL_OK -ne 0 ]; then log "ERROR: both HTTP and PSQL checks failed"; exit 13; fi
if [ $HTTP_OK -ne 0 ]; then exit 11; fi
if [ $PSQL_OK -ne 0 ]; then exit 12; fi
exit 0
