#!/usr/bin/env bash
# ============================================================
# BOOST training-reg backend deploy automation
# Wires the Google Apps Script /exec endpoint into app.js.
#
# Idempotent: safe to rerun.
# Requires: clasp, jq, git, gh; you logged into Google account.
# Run from repo root:  bash scripts/deploy_backend.sh
# ============================================================
set -euo pipefail

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; NC="\033[0m"
log()  { printf "${CYAN}[deploy]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[ ok ]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[warn]${NC} %s\n" "$*"; }
die()  { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; exit 1; }

# --- preflight ---
command -v node  >/dev/null || die "node missing — install Node.js LTS from https://nodejs.org"
command -v npm   >/dev/null || die "npm missing — comes with Node; reinstall Node.js"
command -v git   >/dev/null || die "git missing"
command -v gh    >/dev/null || warn "gh missing — git push only, skip auto-deploy verify"

# Auto-install clasp if missing
if ! command -v clasp >/dev/null 2>&1; then
  log "clasp not found. Installing @google/clasp globally (~30 s)…"
  npm install -g @google/clasp 2>&1 | tail -3
  hash -r 2>/dev/null || true
  if ! command -v clasp >/dev/null 2>&1; then
    # Maybe npm-prefix bin not on PATH (common on Windows). Try again with explicit npm prefix.
    NPM_BIN="$(npm bin -g 2>/dev/null || npm prefix -g 2>/dev/null)"
    [[ -d "$NPM_BIN" ]] && export PATH="$NPM_BIN:$PATH"
    command -v clasp >/dev/null 2>&1 || die "clasp install succeeded but binary not on PATH. Open a new shell and rerun."
  fi
  ok "clasp installed: $(clasp --version 2>&1 | tail -1)"
fi

# JSON helper using Node (avoids jq dependency). Use fs.readFileSync to dodge
# Windows-path quirks in require().
jread() { node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));process.stdout.write((j[process.argv[2]]||'').toString())" "$1" "$2"; }
jread_first() { node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const v=j[process.argv[2]];process.stdout.write(Array.isArray(v)?(v[0]||''):(v||''))" "$1" "$2"; }

[[ -f index.html && -f Code.gs && -f app.js ]] || die "run from repo root"

# --- step 1: clasp login (if needed) ---
if ! clasp list-scripts >/dev/null 2>&1; then
  log "Not logged into clasp. Opening login flow…"
  echo
  warn "Browser will open. Sign in with the Google account that should OWN the Sheet."
  warn "Pre-req: enable Apps Script API at https://script.google.com/home/usersettings (one toggle)."
  echo
  read -rp "Press Enter when API toggle is ON…"
  clasp login
  ok "logged in"
else
  ok "clasp already logged in"
fi

# --- step 2: create bound Sheet + script (skip if already exists) ---
APPS_DIR="apps_script"
mkdir -p "$APPS_DIR"

CLASP_JSON_ABS="$(pwd)/$APPS_DIR/.clasp.json"
if [[ -f "$CLASP_JSON_ABS" ]]; then
  ok "Apps Script project already exists (skipping create)"
  SCRIPT_ID=$(jread "$CLASP_JSON_ABS" scriptId)
  SHEET_ID=$(jread_first "$CLASP_JSON_ABS" parentId)
else
  log "Creating Google Sheet + bound Apps Script project…"
  ( cd "$APPS_DIR" && clasp create-script --type sheets --title "BOOST Training Registrations - UG Portal" )
  SCRIPT_ID=$(jread "$CLASP_JSON_ABS" scriptId)
  SHEET_ID=$(jread_first "$CLASP_JSON_ABS" parentId)
  ok "scriptId=$SCRIPT_ID  sheetId=$SHEET_ID"
fi

[[ -n "${SHEET_ID:-}" ]] || die "Could not derive Sheet ID from .clasp.json"

# --- step 3: prep Code.js with real SHEET_ID + manifest ---
log "Patching Code.js with SHEET_ID + writing appsscript.json manifest…"
sed "s|REPLACE_ME_UG_SPREADSHEET_ID|$SHEET_ID|" Code.gs > "$APPS_DIR/Code.js"

cat > "$APPS_DIR/appsscript.json" <<'JSON'
{
  "timeZone": "Asia/Kolkata",
  "dependencies": {},
  "exceptionLogging": "STACKDRIVER",
  "runtimeVersion": "V8",
  "webapp": {
    "executeAs": "USER_DEPLOYING",
    "access": "ANYONE_ANONYMOUS"
  },
  "oauthScopes": [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/script.send_mail",
    "https://www.googleapis.com/auth/script.external_request"
  ]
}
JSON
ok "files staged"

# --- step 4: push code ---
log "Pushing code to Apps Script…"
( cd "$APPS_DIR" && clasp push --force )
ok "code pushed"

# --- step 5: deploy as Web App ---
log "Deploying Web App (versioned)…"
DEPLOY_OUT=$( cd "$APPS_DIR" && clasp create-deployment --description "v$(date +%Y%m%d-%H%M%S)" )
echo "$DEPLOY_OUT"
DEP_ID=$( echo "$DEPLOY_OUT" | grep -oE 'AKfyc[A-Za-z0-9_-]+' | head -1 )
[[ -n "$DEP_ID" ]] || die "Could not parse deployment ID from clasp output"
EXEC_URL="https://script.google.com/macros/s/$DEP_ID/exec"
ok "deployment URL: $EXEC_URL"

# --- step 6: patch app.js ---
log "Patching app.js APPS_SCRIPT_URL…"
if grep -q "REPLACE_ME_UG_DEPLOYMENT_ID" app.js; then
  sed -i.bak "s|https://script.google.com/macros/s/REPLACE_ME_UG_DEPLOYMENT_ID/exec|$EXEC_URL|" app.js
  rm -f app.js.bak
  ok "app.js patched"
else
  # Already wired — replace existing URL line
  sed -i.bak "s|^const APPS_SCRIPT_URL = .*|const APPS_SCRIPT_URL = \"$EXEC_URL\";|" app.js
  rm -f app.js.bak
  ok "app.js URL refreshed"
fi

# --- step 7: commit + push to GitHub ---
if git diff --quiet app.js; then
  warn "app.js unchanged — skipping commit"
else
  log "Committing + pushing to GitHub…"
  git add app.js
  git commit -m "feat: wire Apps Script backend ($DEP_ID)"
  git push origin main
  ok "pushed"
fi

# --- step 8: print follow-up ---
echo
ok "BACKEND DEPLOYED"
echo
cat <<EOF
  Web App URL : $EXEC_URL
  Sheet ID    : $SHEET_ID
  Sheet       : https://docs.google.com/spreadsheets/d/$SHEET_ID/edit
  Script      : https://script.google.com/d/$SCRIPT_ID/edit

  ONE manual step left (Google forces this on first deploy):
    1. Open the Script editor URL above
    2. Click  Run > setup_   (top toolbar)
    3. Click  Review permissions  →  pick your account  →  Allow
    4. (No need to redeploy; the existing deployment will start serving requests.)

  Test the form at https://devastotra-stack.github.io/boost-training-reg/
  (Pages auto-redeployed via Actions; allow ~30 s.)
EOF
