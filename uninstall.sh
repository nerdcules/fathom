#!/usr/bin/env bash
# Remove Fathom: switch back to the theme that was on before it and, if the
# sign-in screen was installed, give Omarchy's back (asks for your password).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="$HOME/.config/omarchy/themes/fathom"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fathom"
MARKER=".fathom-install"
FALLBACK_THEME="tokyo-night"

previous=$FALLBACK_THEME
[[ -s $STATE_DIR/previous-theme ]] && previous=$(<"$STATE_DIR/previous-theme")

current=$(omarchy theme current 2>/dev/null || true)
if [[ ${current,,} == fathom ]]; then
  omarchy theme set "$previous"
  echo "Switched back to $previous."
fi

if [[ -L $THEME_DIR ]]; then
  rm "$THEME_DIR"
  echo "Removed the link at $THEME_DIR"
elif [[ -f $THEME_DIR/$MARKER ]]; then
  rm -rf "$THEME_DIR"
  echo "Removed $THEME_DIR"
elif [[ -d $THEME_DIR ]]; then
  echo "Left $THEME_DIR alone: Fathom's installer did not make it."
fi

rm -rf "$STATE_DIR"

HYPR="$HOME/.config/hypr"
PLUGINS="$HOME/.config/omarchy/plugins"
hypr_changed=false

# Mini-player: stop it, then remove the bar widget, keys, rules and command.
if [[ -e $HOME/.local/bin/fathom-player || -d $PLUGINS/fathom.player ]]; then
  "$HOME/.local/bin/fathom-player" stop >/dev/null 2>&1 || true
  omarchy plugin disable fathom.player >/dev/null 2>&1 || true
  rm -rf "$PLUGINS/fathom.player"
  rm -f "$HYPR/fathom-player.lua" "$HOME/.local/bin/fathom-player"
  hypr_changed=true
  echo "Removed the mini-player."
fi

# Command Deck: close it, then remove the plugin, key and command.
if [[ -e $HOME/.local/bin/fathom-deck || -d $PLUGINS/fathom.deck ]]; then
  omarchy-shell shell hide fathom.deck >/dev/null 2>&1 || true
  omarchy plugin disable fathom.deck >/dev/null 2>&1 || true
  rm -rf "$PLUGINS/fathom.deck"
  rm -f "$HYPR/fathom-deck.lua" "$HOME/.local/bin/fathom-deck"
  hypr_changed=true
  echo "Removed the Command Deck."
fi

# The block in hyprland.lua that loaded them.
if $hypr_changed; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  main="$HYPR/hyprland.lua"
  [[ -f $main ]] && sed -i "/^-- fathom: begin/,/^-- fathom: end\$/d" "$main"
  hyprctl reload >/dev/null 2>&1 || true
fi

if [[ -d /usr/share/sddm/themes/fathom || -f /etc/sddm.conf.d/99-zz-fathom.conf ]]; then
  if [[ -t 0 ]]; then
    sudo bash "$REPO/signin/install-root.sh" uninstall
  else
    pkexec bash "$REPO/signin/install-root.sh" uninstall
  fi
fi
