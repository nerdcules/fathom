#!/bin/bash
# The root half of Sentinel. install.sh --sentinel runs it with sudo (or a
# password prompt); uninstall.sh runs it with "uninstall".
#
#   install-root.sh install <sentinel dir> [--opensnitch]
#   install-root.sh uninstall
set -euo pipefail
export PATH=/usr/bin

LIB=/usr/local/lib/fathom-sentinel
UNITS=/etc/systemd/system
MARK_SNITCH=$LIB/opensnitch-installed-by-fathom

(( EUID == 0 )) || { echo "install-root.sh: run as root" >&2; exit 1; }

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

remove_fathom_rules() {
  # Firewall rules the buttons added, found by their comments.
  local hex_lock hex_block line spec
  hex_lock=$(printf 'fathom-lockdown' | od -An -tx1 | tr -d ' \n')
  hex_block=$(printf 'fathom-block' | od -An -tx1 | tr -d ' \n')
  [[ -f /etc/ufw/user.rules ]] || return 0
  grep -h "^### tuple ###" /etc/ufw/user.rules /etc/ufw/user6.rules 2>/dev/null |
    grep -E "comment=($hex_lock|$hex_block)$" | while read -r line; do
      # ### tuple ### deny any any 0.0.0.0/0 any <src> in[_<iface>] comment=...
      read -r _ _ _ action _ _ _ _ src dir _ <<<"$line"
      if [[ $dir == in_* ]]; then
        spec=(deny in on "${dir#in_}")
      else
        spec=(deny from "${src%/*}")
      fi
      ufw delete "${spec[@]}" >/dev/null 2>&1 || true
    done
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
  rm -rf "$LIB" /var/lib/fathom-sentinel
  echo "Removed Sentinel's root parts."
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
