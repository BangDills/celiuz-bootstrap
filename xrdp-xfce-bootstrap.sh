#!/usr/bin/env bash
set -Eeuo pipefail

# XFCE + XRDP bootstrap for Ubuntu/Debian VPS
# Based on user's requested commands, with safer firewall handling:
# - allow SSH/OpenSSH before enabling UFW so you do not lock yourself out
# - install dbus-x11 for XFCE session stability under XRDP
# - set ~/.xsession for the target user

TARGET_USER="${TARGET_USER:-${SUDO_USER:-root}}"
ENABLE_UFW="${ENABLE_UFW:-true}"
ALLOW_SSH="${ALLOW_SSH:-true}"
ALLOW_RDP_FROM="${ALLOW_RDP_FROM:-any}" # e.g. 1.2.3.4 for tighter access, or 'any'

log() { printf '\033[1;32m[%s]\033[0m %s\n' "$(date -Is)" "$*"; }
warn() { printf '\033[1;33m[%s WARN]\033[0m %s\n' "$(date -Is)" "$*" >&2; }
fail() { printf '\033[1;31m[%s ERROR]\033[0m %s\n' "$(date -Is)" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
XFCE + XRDP bootstrap

Usage as root:
  bash xrdp-xfce-bootstrap.sh

Optional env vars:
  TARGET_USER=root          User whose ~/.xsession will be set (default root if running as root)
  ENABLE_UFW=true|false     Enable UFW and add firewall rules (default true)
  ALLOW_SSH=true|false      Allow OpenSSH before UFW enable (default true)
  ALLOW_RDP_FROM=any        Allow RDP from anywhere (default) or a single IP/CIDR

Examples:
  bash xrdp-xfce-bootstrap.sh
  TARGET_USER=root ALLOW_RDP_FROM=203.0.113.10 bash xrdp-xfce-bootstrap.sh
  ENABLE_UFW=false bash xrdp-xfce-bootstrap.sh
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

[[ "$(id -u)" == "0" ]] || fail "Run as root, or use sudo."
command -v apt-get >/dev/null 2>&1 || fail "This script expects Ubuntu/Debian with apt-get."
command -v systemctl >/dev/null 2>&1 || fail "systemd/systemctl is required."

if ! id "$TARGET_USER" >/dev/null 2>&1; then
  fail "TARGET_USER does not exist: $TARGET_USER"
fi

USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || fail "Cannot determine home directory for $TARGET_USER"

log "Installing XFCE, XRDP, dbus-x11, and UFW"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y xfce4 xfce4-goodies dbus-x11 xrdp ufw

log "Configuring XFCE session for user: $TARGET_USER ($USER_HOME/.xsession)"
printf 'xfce4-session\n' > "$USER_HOME/.xsession"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/.xsession" 2>/dev/null || chown "$TARGET_USER" "$USER_HOME/.xsession"
chmod 644 "$USER_HOME/.xsession"

# Make XRDP prefer XFCE for this machine as well.
if [[ -f /etc/xrdp/startwm.sh ]]; then
  cp -a /etc/xrdp/startwm.sh "/etc/xrdp/startwm.sh.bak.$(date -u +%Y%m%d_%H%M%S)"
fi

log "Enabling and restarting XRDP"
systemctl enable xrdp
systemctl restart xrdp

if [[ "$ENABLE_UFW" == "true" ]]; then
  log "Configuring UFW firewall"
  if [[ "$ALLOW_SSH" == "true" ]]; then
    ufw allow OpenSSH || ufw allow 22/tcp || true
  fi

  if [[ "$ALLOW_RDP_FROM" == "any" ]]; then
    ufw allow 3389/tcp
  else
    ufw allow from "$ALLOW_RDP_FROM" to any port 3389 proto tcp
  fi

  # Non-interactive equivalent of: sudo ufw enable
  ufw --force enable
else
  warn "ENABLE_UFW=false, skipping firewall enable/rules"
fi

log "Verification"
systemctl is-enabled xrdp || true
systemctl is-active xrdp || true
ss -ltnp 2>/dev/null | grep ':3389' || warn "Port 3389 not visible in ss output yet"
ufw status verbose || true

cat <<EOF

XRDP + XFCE bootstrap complete.

Connect via RDP to:
  <VPS-IP>:3389

Login user:
  $TARGET_USER

Session file:
  $USER_HOME/.xsession -> xfce4-session

If you cannot connect, check:
  systemctl status xrdp --no-pager -l
  journalctl -u xrdp -n 100 --no-pager
  ufw status verbose
EOF
