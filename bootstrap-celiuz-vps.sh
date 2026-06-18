#!/usr/bin/env bash
set -Eeuo pipefail

# Celiuz/Hermes VPS real bootstrap
# - Installs base runtime: curl/git/gpg/python/node22/npm/gh/VS Code/9router/codex/opencode/Hermes
# - Retrieves latest encrypted Hermes backup from a direct URL, local file, Google Drive file id,
#   or public Google Drive folder URL/id via gdown
# - Decrypts and restores /root/.hermes, /root/.9router, and relevant systemd services
# - Starts/verifies 9Router and Hermes gateway
#
# Safe default: never stores passphrase unless you pass PASSPHRASE_FILE yourself.

SCRIPT_VERSION="2026-06-18.2"
WORKDIR="${WORKDIR:-/root/hermes-bootstrap-work}"
HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
NODE_MAJOR="${NODE_MAJOR:-22}"
START_GATEWAY="${START_GATEWAY:-true}"
START_9ROUTER="${START_9ROUTER:-true}"
KEEP_WORKDIR="${KEEP_WORKDIR:-true}"

log() { printf '\033[1;32m[%s]\033[0m %s\n' "$(date -Is)" "$*"; }
warn() { printf '\033[1;33m[%s WARN]\033[0m %s\n' "$(date -Is)" "$*" >&2; }
err() { printf '\033[1;31m[%s ERROR]\033[0m %s\n' "$(date -Is)" "$*" >&2; }
fail() { err "$*"; exit 1; }

usage() {
  cat <<'EOF'
Celiuz/Hermes VPS bootstrap

Usage examples on a fresh Ubuntu/Debian VPS as root:

  # Best: direct encrypted backup URL + prompt for passphrase
  BACKUP_URL='https://example.com/hermes-backup-latest.tar.gz.gpg' bash bootstrap-celiuz-vps.sh

  # Local/scp-uploaded backup file
  BACKUP_FILE='/root/hermes-backup-20260617_030000.tar.gz.gpg' bash bootstrap-celiuz-vps.sh

  # Public Google Drive file id
  BACKUP_DRIVE_FILE_ID='FILE_ID' bash bootstrap-celiuz-vps.sh

  # Public Google Drive folder URL/id containing hermes-backup-*.tar.gz.gpg files
  BACKUP_DRIVE_FOLDER_URL='https://drive.google.com/drive/folders/FOLDER_ID' bash bootstrap-celiuz-vps.sh
  BACKUP_DRIVE_FOLDER_ID='FOLDER_ID' bash bootstrap-celiuz-vps.sh

Optional env vars:
  PASSPHRASE='...'              Non-interactive passphrase (avoid shell history if possible)
  PASSPHRASE_FILE='/path/file'  Read passphrase from file
  START_GATEWAY=true|false      Start hermes-gateway after restore (default true)
  START_9ROUTER=true|false      Start 9router after restore (default true)
  WORKDIR=/root/hermes-bootstrap-work

Security:
  Prefer entering the passphrase interactively or using PASSPHRASE_FILE from a temporary file.
  Do not paste real secrets into public shell history.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

[[ "$(id -u)" == "0" ]] || fail "Run as root on the new VPS."
command -v systemctl >/dev/null 2>&1 || fail "systemd/systemctl is required."

on_error() {
  local code=$?
  err "Bootstrap failed at line $1 (exit $code). Workdir: $WORKDIR"
  err "If restore already swapped state, check rollback dirs under $WORKDIR."
  exit "$code"
}
trap 'on_error $LINENO' ERR

install_base_packages() {
  log "Installing base packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl ca-certificates git gnupg tar gzip xz-utils python3 python3-venv python3-pip build-essential jq npm gh
}

install_node22() {
  log "Installing Node.js ${NODE_MAJOR}.x via n"
  npm install -g n
  n "$NODE_MAJOR"
  hash -r || true
  export PATH="/usr/local/bin:$PATH"
  node --version
  npm --version
}

install_ai_clis() {
  log "Installing 9Router, Codex CLI, OpenCode CLI"
  npm install -g 9router @openai/codex opencode-ai@latest
  command -v 9router >/dev/null && 9router --version || true
  command -v codex >/dev/null && codex --version || true
  command -v opencode >/dev/null && opencode --version || true
  gh --version | head -1 || true
}

install_vscode_root_launcher() {
  log "Installing Visual Studio Code and code-root launcher"

  install -d -m 0755 /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/packages.microsoft.gpg ]]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
    chmod 0644 /etc/apt/keyrings/packages.microsoft.gpg
  fi

  cat > /etc/apt/sources.list.d/vscode.list <<'EOF'
deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main
EOF

  apt-get update
  apt-get install -y code

  cat > /usr/local/bin/code-root <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REAL_CODE="/usr/bin/code"
USER_DATA_DIR="/root/.vscode-root"

if [[ ! -x "$REAL_CODE" ]]; then
  echo "Error: $REAL_CODE not found or not executable" >&2
  exit 127
fi

mkdir -p "$USER_DATA_DIR"

has_no_sandbox=0
has_user_data_dir=0
for arg in "$@"; do
  [[ "$arg" == "--no-sandbox" ]] && has_no_sandbox=1
  [[ "$arg" == --user-data-dir* ]] && has_user_data_dir=1
done

args=()
[[ "$has_no_sandbox" -eq 0 ]] && args+=("--no-sandbox")
[[ "$has_user_data_dir" -eq 0 ]] && args+=("--user-data-dir=$USER_DATA_DIR")

exec "$REAL_CODE" "${args[@]}" "$@"
EOF
  chmod 0755 /usr/local/bin/code-root

  cat > /usr/share/applications/code-root.desktop <<'EOF'
[Desktop Entry]
Name=Visual Studio Code (Root)
Comment=Open VS Code as root with isolated profile
GenericName=Text Editor
Exec=/usr/local/bin/code-root --new-window /root
Icon=code
Type=Application
StartupNotify=true
Categories=Utility;TextEditor;Development;IDE;
EOF
  chmod 0644 /usr/share/applications/code-root.desktop

  code --version | head -3 || true
  code-root --version | head -3 || true
}

install_hermes() {
  if command -v hermes >/dev/null 2>&1; then
    log "Hermes already installed: $(command -v hermes)"
    hermes --version || true
    return
  fi
  log "Installing Hermes Agent"
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  export PATH="/usr/local/bin:/root/.local/bin:$PATH"
  command -v hermes >/dev/null 2>&1 || fail "Hermes command not found after install"
  hermes --version || true
}

setup_workdir() {
  mkdir -p "$WORKDIR"
  chmod 700 "$WORKDIR"
}

obtain_backup() {
  log "Retrieving encrypted backup"
  mkdir -p "$WORKDIR/downloads"
  local out="$WORKDIR/hermes-backup.tar.gz.gpg"

  if [[ -n "${BACKUP_FILE:-}" ]]; then
    [[ -f "$BACKUP_FILE" ]] || fail "BACKUP_FILE not found: $BACKUP_FILE"
    cp -f "$BACKUP_FILE" "$out"
  elif [[ -n "${BACKUP_URL:-}" ]]; then
    curl -fL --retry 3 --retry-delay 3 "$BACKUP_URL" -o "$out"
  elif [[ -n "${BACKUP_DRIVE_FILE_ID:-}" ]]; then
    python3 -m venv "$WORKDIR/.venv"
    # shellcheck disable=SC1091
    . "$WORKDIR/.venv/bin/activate"
    pip install -q --upgrade pip gdown
    gdown "https://drive.google.com/uc?id=${BACKUP_DRIVE_FILE_ID}" -O "$out"
  elif [[ -n "${BACKUP_DRIVE_FOLDER_URL:-}${BACKUP_DRIVE_FOLDER_ID:-}" ]]; then
    python3 -m venv "$WORKDIR/.venv"
    # shellcheck disable=SC1091
    . "$WORKDIR/.venv/bin/activate"
    pip install -q --upgrade pip gdown
    local folder="${BACKUP_DRIVE_FOLDER_URL:-https://drive.google.com/drive/folders/${BACKUP_DRIVE_FOLDER_ID}}"
    rm -rf "$WORKDIR/gdrive-folder"
    mkdir -p "$WORKDIR/gdrive-folder"
    gdown --folder "$folder" -O "$WORKDIR/gdrive-folder" --remaining-ok
    local latest
    latest="$(find "$WORKDIR/gdrive-folder" -type f -name 'hermes-backup-*.tar.gz.gpg' | sort | tail -1)"
    [[ -n "$latest" ]] || fail "No hermes-backup-*.tar.gz.gpg found in Google Drive folder"
    cp -f "$latest" "$out"
  else
    fail "Set BACKUP_FILE, BACKUP_URL, BACKUP_DRIVE_FILE_ID, BACKUP_DRIVE_FOLDER_URL, or BACKUP_DRIVE_FOLDER_ID."
  fi

  [[ -s "$out" ]] || fail "Downloaded backup is empty: $out"
  chmod 600 "$out"
  log "Backup ready: $out ($(du -h "$out" | cut -f1), sha256=$(sha256sum "$out" | awk '{print $1}'))"
}

make_passfile() {
  local passfile="$WORKDIR/passphrase.tmp"
  chmod 700 "$WORKDIR"
  if [[ -n "${PASSPHRASE_FILE:-}" ]]; then
    [[ -s "$PASSPHRASE_FILE" ]] || fail "PASSPHRASE_FILE missing/empty: $PASSPHRASE_FILE"
    cp -f "$PASSPHRASE_FILE" "$passfile"
  elif [[ -n "${PASSPHRASE:-}" ]]; then
    printf '%s' "$PASSPHRASE" > "$passfile"
  else
    printf 'Enter Hermes backup passphrase: ' >&2
    stty -echo
    IFS= read -r pass
    stty echo
    printf '\n' >&2
    printf '%s' "$pass" > "$passfile"
  fi
  chmod 600 "$passfile"
  printf '%s' "$passfile"
}

verify_and_decrypt() {
  log "Decrypting and verifying backup"
  local passfile
  passfile="$(make_passfile)"
  local enc="$WORKDIR/hermes-backup.tar.gz.gpg"
  local plain="$WORKDIR/hermes-backup.tar.gz"
  gpg --batch --yes --pinentry-mode loopback --passphrase-file "$passfile" --output "$plain" --decrypt "$enc"
  rm -f "$passfile"
  chmod 600 "$plain"
  tar -tzf "$plain" > "$WORKDIR/archive_listing.txt"

  python3 - <<PY
from pathlib import Path
paths = Path('$WORKDIR/archive_listing.txt').read_text(errors='replace').splitlines()
bad = [p for p in paths if p.startswith('/') or '..' in p.split('/')]
if bad:
    raise SystemExit('Unsafe archive paths: ' + repr(bad[:10]))
required_any = [
    ('Hermes state', ['root/.hermes/', '.hermes/']),
]
for label, prefixes in required_any:
    if not any(any(p == pref.rstrip('/') or p.startswith(pref) for pref in prefixes) for p in paths):
        raise SystemExit(f'Missing {label}: expected one of {prefixes}')
print('Archive entries:', len(paths))
for needle in ['root/.hermes/memories/MEMORY.md','root/.hermes/memories/USER.md','root/.hermes/state.db','root/.9router/db/data.sqlite','etc/systemd/system/9router.service']:
    print(f'{needle}:', any(p == needle or p.startswith(needle.rstrip('/') + '/') for p in paths))
PY
  log "Backup decrypt/list validation OK"
}

rollback_current_state() {
  log "Creating rollback of current state if present"
  local stamp rollback
  stamp="$(date -u +%Y%m%d_%H%M%S)"
  rollback="$WORKDIR/current-before-restore-$stamp.tar.gz"
  tar_args=()
  [[ -d /root/.hermes ]] && tar_args+=(root/.hermes)
  [[ -d /root/.9router ]] && tar_args+=(root/.9router)
  [[ -f /etc/systemd/system/hermes-gateway.service ]] && tar_args+=(etc/systemd/system/hermes-gateway.service)
  [[ -f /etc/systemd/system/9router.service ]] && tar_args+=(etc/systemd/system/9router.service)
  if [[ ${#tar_args[@]} -gt 0 ]]; then
    tar --ignore-failed-read --warning=no-file-changed -czf "$rollback" -C / "${tar_args[@]}" || true
    chmod 600 "$rollback"
    log "Rollback archive: $rollback ($(du -h "$rollback" | cut -f1))"
  else
    log "No existing Hermes/9Router state to rollback"
  fi
}

extract_and_restore() {
  log "Extracting backup to staging"
  rm -rf "$WORKDIR/staging"
  mkdir -p "$WORKDIR/staging"
  tar -xzf "$WORKDIR/hermes-backup.tar.gz" -C "$WORKDIR/staging"

  rollback_current_state

  local stamp="$(date -u +%Y%m%d_%H%M%S)"
  [[ -d /root/.hermes ]] && mv /root/.hermes "$WORKDIR/.hermes.before-$stamp"
  [[ -d /root/.9router ]] && mv /root/.9router "$WORKDIR/.9router.before-$stamp"

  if [[ -d "$WORKDIR/staging/root/.hermes" ]]; then
    cp -a "$WORKDIR/staging/root/.hermes" /root/.hermes
  elif [[ -d "$WORKDIR/staging/.hermes" ]]; then
    cp -a "$WORKDIR/staging/.hermes" /root/.hermes
  else
    fail "No .hermes directory found in staging"
  fi

  if [[ -d "$WORKDIR/staging/root/.9router" ]]; then
    cp -a "$WORKDIR/staging/root/.9router" /root/.9router
  elif [[ -d "$WORKDIR/staging/.9router" ]]; then
    cp -a "$WORKDIR/staging/.9router" /root/.9router
  else
    warn "No .9router directory found in backup"
  fi

  mkdir -p /etc/systemd/system
  [[ -f "$WORKDIR/staging/etc/systemd/system/hermes-gateway.service" ]] && cp -a "$WORKDIR/staging/etc/systemd/system/hermes-gateway.service" /etc/systemd/system/hermes-gateway.service
  [[ -f "$WORKDIR/staging/etc/systemd/system/9router.service" ]] && cp -a "$WORKDIR/staging/etc/systemd/system/9router.service" /etc/systemd/system/9router.service

  # Normalize restored 9Router unit to the current npm global path.
  if [[ -f /etc/systemd/system/9router.service ]]; then
    local rbin
    rbin="$(command -v 9router || true)"
    [[ -n "$rbin" ]] || rbin="/usr/local/bin/9router"
    python3 - <<PY
from pathlib import Path
p=Path('/etc/systemd/system/9router.service')
s=p.read_text()
lines=[]
changed=False
for line in s.splitlines():
    if line.startswith('ExecStart='):
        lines.append('ExecStart=$rbin --port 20128 --host 127.0.0.1 --no-browser --skip-update --log')
        changed=True
    elif line.startswith('Environment=HOME='):
        lines.append('Environment=HOME=/root')
    else:
        lines.append(line)
if not changed:
    lines.append('ExecStart=$rbin --port 20128 --host 127.0.0.1 --no-browser --skip-update --log')
p.write_text('\n'.join(lines)+'\n')
PY
  fi

  chmod 700 /root/.hermes 2>/dev/null || true
  chmod 700 /root/.9router 2>/dev/null || true
  log "State restore copied into /root/.hermes and /root/.9router"
}

install_or_refresh_gateway_service() {
  log "Installing/enabling Hermes gateway service"
  export HERMES_HOME=/root/.hermes
  export HOME=/root
  export PATH="/usr/local/bin:/root/.local/bin:$PATH"
  if command -v hermes >/dev/null 2>&1; then
    # Prefer official installer; if it fails, use restored service unit.
    hermes gateway install || warn "hermes gateway install failed; will try restored systemd unit"
  fi
  systemctl daemon-reload
  if [[ -f /etc/systemd/system/hermes-gateway.service ]]; then
    systemctl enable hermes-gateway.service || true
    if [[ "$START_GATEWAY" == "true" ]]; then
      systemctl restart hermes-gateway.service || warn "Failed to restart hermes-gateway; check journalctl -u hermes-gateway"
    fi
  else
    warn "No hermes-gateway.service found/installed"
  fi
}

start_services() {
  log "Starting services"
  systemctl daemon-reload
  if [[ "$START_9ROUTER" == "true" && -f /etc/systemd/system/9router.service ]]; then
    systemctl enable --now 9router.service
  fi
  install_or_refresh_gateway_service
}

verify_services() {
  log "Verifying restored system"
  export PATH="/usr/local/bin:/root/.local/bin:$PATH"
  printf 'node: '; node --version || true
  printf 'npm: '; npm --version || true
  printf '9router: '; 9router --version || true
  printf 'codex: '; codex --version || true
  printf 'opencode: '; opencode --version || true
  printf 'gh: '; gh --version | head -1 || true
  printf 'code: '; code --version | head -1 || true
  printf 'code-root: '; code-root --version | head -1 || true
  printf 'hermes: '; hermes --version || true

  if systemctl is-active --quiet 9router.service; then
    log "9router.service active"
  else
    warn "9router.service not active"
  fi
  curl -fsS --max-time 10 http://127.0.0.1:20128/api/health && printf '\n' || warn "9Router health endpoint failed"

  if systemctl is-active --quiet hermes-gateway.service; then
    log "hermes-gateway.service active"
  else
    warn "hermes-gateway.service not active"
  fi

  log "Recent Hermes memory files:"
  stat -c '%n | %y | %s bytes' /root/.hermes/memories/MEMORY.md /root/.hermes/memories/USER.md 2>/dev/null || true
  log "Bootstrap complete"
}

main() {
  log "Celiuz bootstrap version $SCRIPT_VERSION"
  setup_workdir
  install_base_packages
  install_node22
  install_ai_clis
  install_vscode_root_launcher
  install_hermes
  obtain_backup
  verify_and_decrypt
  extract_and_restore
  start_services
  verify_services

  if [[ "$KEEP_WORKDIR" != "true" ]]; then
    rm -rf "$WORKDIR"
  else
    warn "Workdir kept for audit/rollback: $WORKDIR"
    warn "It contains decrypted backup unless you delete it. Remove after verification: rm -rf '$WORKDIR'"
  fi
}

main "$@"
