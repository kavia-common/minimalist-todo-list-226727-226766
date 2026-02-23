#!/usr/bin/env bash
set -euo pipefail
# testing-01: safe Supabase/Postgres healthcheck
WORKSPACE="/home/kavia/workspace/code-generation/minimalist-todo-list-226727-226766/database"
LOG="$WORKSPACE/setup.log"
mkdir -p "$(dirname "$LOG")"
HEALTH_SCRIPT="$WORKSPACE/healthcheck.sh"
cat > "$HEALTH_SCRIPT" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
LOG="/dev/stdout"
log(){ echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) testing-01: $*" | tee -a "$LOG"; }
# Controlled .env parser: only simple KEY=VALUE lines, strip surrounding quotes, ignore unsafe values
if [ -f .env ]; then
  while IFS='=' read -r key val || [ -n "$key" ]; do
    # skip empty and comments
    case "$key" in ''|#*) continue ;; esac
    key=$(echo "$key" | sed 's/[^A-Za-z0-9_].*//')
    [ -z "$key" ] && continue
    # rejoin remainder if = in value (read stops at first '=')
    if ! echo "$val" | grep -q "" >/dev/null 2>&1; then :; fi
    # read full raw line to capture = in value
    raw=$(grep -E "^$key=" .env | sed -n '1p' || true)
    val=${raw#*=}
    # strip surrounding single or double quotes and surrounding whitespace
    val=$(echo "$val" | sed -E 's/^\s*"(.*)"\s*$/\1/; s/^\s*'"'"'(.*)'"'"'\s*$/\1/; s/^\s+//; s/\s+$//')
    # reject values containing shell meta-chars to avoid accidental execution
    case "$val" in *\$*|*`*|*\(|*\)|*\{*|*\}*|*\;*|*\&*|*\|* ) val="" ;; esac
    export "$key"="$val"
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env || true)
fi
# Heuristic checks
SU_URL="${SUPABASE_URL:-}"
SU_KEY="${SUPABASE_ANON_KEY:-}"
[ -z "$SU_URL" ] && log "WARN: SUPABASE_URL not set"
[ -z "$SU_KEY" ] && log "WARN: SUPABASE_ANON_KEY not set"
HTTP_OK=1; PSQL_OK=1
# HTTP probe with timeout and small retries (non-destructive)
if [ -n "$SU_URL" ] && [ -n "$SU_KEY" ]; then
  # normalize URL (no trailing slash)
  base="${SU_URL%/}"
  for i in 1 2 3; do
    if curl -fsS --connect-timeout 3 --max-time 8 "$base/rest/v1" -H "apikey: $SU_KEY" -o /dev/null 2>/dev/null; then HTTP_OK=0; log "HTTP OK"; break; fi
    sleep 1
  done
  if [ $HTTP_OK -ne 0 ]; then
    if curl -fsS --connect-timeout 3 --max-time 8 "$base" -o /dev/null 2>/dev/null; then HTTP_OK=0; log "HTTP OK (root)"; fi
  fi
else
  log "INFO: Skipping HTTP probe because SUPABASE_URL or SUPABASE_ANON_KEY missing"
fi
# psql probe using inline PGPASSWORD, non-interactive
if command -v psql >/dev/null 2>&1; then
  PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}" PGPASS="${PGPASSWORD:-}" PGDB="${PGDATABASE:-postgres}"
  # build connection string without embedding password
  PSQL_CONN="postgresql://$PGUSER@$PGHOST:$PGPORT/$PGDB"
  if PGPASSWORD="$PGPASS" psql "$PSQL_CONN" -tA -c '\\conninfo' >/dev/null 2>&1; then
    PSQL_OK=0; log "PSQL OK"
  else
    log "PSQL UNREACHABLE ($PSQL_CONN)"
  fi
else
  log "INFO: psql not available; skipping PSQL probe"
fi
# Decide exit code
if [ $HTTP_OK -ne 0 ] && [ $PSQL_OK -ne 0 ]; then
  log "ERROR: both HTTP and PSQL checks failed"
  exit 13
fi
if [ $HTTP_OK -ne 0 ]; then
  exit 11
fi
if [ $PSQL_OK -ne 0 ]; then
  exit 12
fi
exit 0
BASH

# ensure health script is executable and run it, appending to workspace log
chmod +x "$HEALTH_SCRIPT"
# run inside workspace so .env resolution is local
pushd "$WORKSPACE" >/dev/null
# ensure log exists and is owned appropriately
: >> "$LOG"
# run and capture exit code
"$HEALTH_SCRIPT" 2>&1 | tee -a "$LOG" || true
popd >/dev/null
