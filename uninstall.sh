#!/usr/bin/env bash
# Remove Fathom and switch back to the theme that was on before it.
set -euo pipefail

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
