#!/bin/bash
# The root half of Crumbs: the helper that writes Fathom's cookie rules into
# the browsers' managed-policy folders. install.sh --crumbs runs it with sudo
# (or a password prompt); uninstall.sh runs it with "uninstall", which also
# takes the rules out.
#
#   install-root.sh install <crumbs dir>
#   install-root.sh uninstall
set -euo pipefail
export PATH=/usr/bin

LIB=/usr/local/lib/fathom-crumbs

(( EUID == 0 )) || { echo "install-root.sh: run as root" >&2; exit 1; }

case "${1:-}" in
  install)
    [[ -f ${2:-}/root/policy ]] || { echo "install-root.sh: no Crumbs folder at '${2:-}'" >&2; exit 2; }
    install -d -m 0755 "$LIB"
    install -m 0755 "$2/root/policy" "$LIB/policy"
    echo "Installed Crumbs' blocking helper."
    ;;
  uninstall)
    [[ -x $LIB/policy ]] && "$LIB/policy" clear || true
    rm -rf "$LIB"
    ;;
  *)
    echo "usage: install-root.sh install <crumbs dir> | uninstall" >&2
    exit 2
    ;;
esac
