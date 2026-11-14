#!/usr/bin/env bash
# The part of the sign-in install that needs root. install.sh and uninstall.sh
# run it through sudo (or pkexec when there is no terminal).
#
#   install-root.sh install <theme-dir>   copy the SDDM theme and select it
#   install-root.sh uninstall             remove both again
#
# It touches only what it owns: the theme folder and its own config file,
# which sorts after Omarchy's 99-omarchy-login.conf so it wins. Omarchy's
# files are left as they are, so removing ours brings Omarchy's screen back.
set -euo pipefail

DEST=/usr/share/sddm/themes/fathom
CONF=/etc/sddm.conf.d/99-zz-fathom.conf

case ${1:-} in
  install)
    src=${2:-}
    if [[ ! -f $src/Main.qml || ! -f $src/metadata.desktop ]]; then
      echo "install-root.sh: '$src' is not an SDDM theme folder." >&2
      exit 1
    fi
    rm -rf "$DEST.new"
    cp -rL "$src" "$DEST.new"
    chown -R root:root "$DEST.new"
    chmod -R u=rwX,go=rX "$DEST.new"
    rm -rf "$DEST"
    mv "$DEST.new" "$DEST"
    mkdir -p "$(dirname "$CONF")"
    cat >"$CONF" <<'EOF'
# Added by Fathom (https://github.com/nerdcules/fathom).
# Delete this file to go back to Omarchy's sign-in screen.
[Theme]
Current=fathom
EOF
    echo "Installed the Fathom sign-in screen."
    ;;
  uninstall)
    rm -f "$CONF"
    rm -rf "$DEST"
    echo "Removed the Fathom sign-in screen."
    ;;
  *)
    echo "Usage: install-root.sh install <theme-dir> | uninstall" >&2
    exit 2
    ;;
esac
