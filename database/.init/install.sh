#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/minimalist-todo-list-226727-226766/database"
LOG="$WORKSPACE/setup.log"
cd "$WORKSPACE"
# ensure package.json with a pinned minimal dependency if absent
if [ ! -f package.json ]; then
  cat > package.json <<'JSON'
{ "name": "minimal-todo-db", "private": true, "dependencies": { "@supabase/supabase-js": "^2.0.0" } }
JSON
fi
# compute checksum to detect changes
PKGCHK="$(sha256sum package.json 2>/dev/null || echo '')"
LASTCHKFILE="$WORKSPACE/.package.json.chk"
LASTCHK="$(cat "$LASTCHKFILE" 2>/dev/null || true)"
if [ "$PKGCHK" != "$LASTCHK" ] || [ ! -d node_modules ]; then
  if [ -f package-lock.json ]; then
    npm ci --no-audit --no-fund >>"$LOG" 2>&1 || { echo "dependencies-01: npm ci failed (see $LOG)" | tee -a "$LOG" >&2; exit 7; }
  else
    npm i --no-audit --no-fund >>"$LOG" 2>&1 || { echo "dependencies-01: npm i failed (see $LOG)" | tee -a "$LOG" >&2; exit 7; }
  fi
  echo "$PKGCHK" > "$LASTCHKFILE"
fi
# smoke test: require the module without network calls
node -e "try{const s=require('@supabase/supabase-js'); if(!s) throw Error('import-failed'); console.log('IMPORT_OK');}catch(e){console.error('dependencies-01: ERROR importing @supabase/supabase-js',e); process.exit(8);}"
