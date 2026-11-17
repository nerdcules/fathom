#!/bin/bash
# The root half of Sentinel. install.sh --sentinel runs it with sudo (or a
# password prompt); uninstall.sh runs it with "uninstall".
#
#   install-root.sh install <sentinel dir> [--opensnitch]
#   install-root.sh uninstall
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Tests set FATHOM_SENTINEL_ROOT to a scratch folder and FATHOM_SENTINEL_PATH
# to stand-in commands; sudo and pkexec drop both, so in use this is /.
ROOT=${FATHOM_SENTINEL_ROOT:-}
if [[ -n $ROOT ]]; then
  export PATH="${FATHOM_SENTINEL_PATH:?}:/usr/bin" FATHOM_SENTINEL_ETC="$ROOT/etc"
else
  export PATH=/usr/bin
  (( EUID == 0 )) || { echo "install-root.sh: run as root" >&2; exit 1; }
fi

LIB=$ROOT/usr/local/lib/fathom-sentinel
UNITS=$ROOT/etc/systemd/system
MARK_SNITCH=$LIB/opensnitch-installed-by-fathom

install_parts() {
  local src=$1 snitch=$2
  install -d -m 0755 "$LIB"
  install -m 0755 "$src/root/admin" "$LIB/admin"
  install -m 0755 "$src/root/check-files" "$LIB/check-files"
  install -m 0644 "$src/systemd/fathom-sentinel-files.service" "$UNITS/fathom-sentinel-files.service"
  install -m 0644 "$src/systemd/fathom-sentinel-files.timer" "$UNITS/fathom-sentinel-files.timer"
  systemctl daemon-reload
  systemctl enable --now fathom-sentinel-files.timer
  # The first check sets the baseline; later ones report what changed.
  systemctl start --no-block fathom-sentinel-files.service
  echo "Installed Sentinel's file check and firewall buttons."

  if $snitch; then
    if ! pacman -Q opensnitch >/dev/null 2>&1; then
      pacman -S --needed --noconfirm opensnitch
      touch "$MARK_SNITCH"
    fi
    systemctl enable --now opensnitchd.service
    echo "OpenSnitch is on. Its window asks the first time each app connects somewhere new."
  fi
}

# The firewall rules the buttons added: only rules with Fathom's comment and
# shape, each removed by its full description, comment included, so a rule
# of yours that matches one of them is kept. The helper names any it
# leaves. It is this copy, not the installed one, so rules an older install
# added go by today's checks.
rules_left=false
remove_fathom_rules() {
  command -v ufw >/dev/null || return 0
  python3 -I "$HERE/root/admin" remove-all || rules_left=true
}

uninstall_parts() {
  systemctl disable --now fathom-sentinel-files.timer >/dev/null 2>&1 || true
  rm -f "$UNITS/fathom-sentinel-files.service" "$UNITS/fathom-sentinel-files.timer"
  systemctl daemon-reload
  remove_fathom_rules
  if [[ -f $MARK_SNITCH ]]; then
    systemctl disable --now opensnitchd.service >/dev/null 2>&1 || true
    pacman -Rns --noconfirm opensnitch || true
    echo "Removed OpenSnitch (Fathom had installed it)."
  fi
  rm -rf "$LIB" "$ROOT/var/lib/fathom-sentinel"
  echo "Removed Sentinel's root parts."
  if $rules_left; then
    echo "install-root.sh: some firewall rules were left; see above." >&2
    return 3
  fi
}

case "${1:-}" in
  install)
    [[ -d ${2:-} ]] || { echo "install-root.sh: give the sentinel folder" >&2; exit 2; }
    snitch=false
    [[ ${3:-} == --opensnitch ]] && snitch=true
    install_parts "$2" "$snitch"
    ;;
  uninstall) uninstall_parts ;;
  *) echo "Usage: install-root.sh install <sentinel dir> [--opensnitch] | uninstall" >&2; exit 2 ;;
esac
