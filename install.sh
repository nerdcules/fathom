#!/usr/bin/env bash
# Install Fathom onto an Omarchy machine. Run ./install.sh --help for options.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$HOME/.config/omarchy/themes"
THEME_DIR="$THEMES_DIR/fathom"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fathom"
MARKER=".fathom-install"

skin=false
link=false
apply=true

usage() {
  cat <<EOF
Usage: ./install.sh [options]

  --skin       Install the Fathom theme (the default when no part is named)
  --link       Symlink the theme to this repo instead of copying it, so edits
               here show up after 'omarchy theme set fathom'
  --no-apply   Install without switching to the theme
  -h, --help   Show this help

Command Deck widgets, apps, the sign-in screen and face login will be added
as options here as they are built.
EOF
}

while (($#)); do
  case $1 in
    --skin) skin=true ;;
    --link) link=true ;;
    --no-apply) apply=false ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "install.sh: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# No part named: install every part that exists so far.
$skin || skin=true

if ! command -v omarchy >/dev/null; then
  echo "install.sh: Fathom needs Omarchy (https://omarchy.org)." >&2
  exit 1
fi

install_skin() {
  mkdir -p "$THEMES_DIR" "$STATE_DIR"

  # Remember the theme to go back to on uninstall, unless Fathom is already on.
  local current
  current=$(omarchy theme current 2>/dev/null || true)
  if [[ -n $current && ${current,,} != fathom ]]; then
    printf '%s\n' "$current" >"$STATE_DIR/previous-theme"
  fi

  # A fathom theme folder this script did not make is the user's: keep it.
  if [[ -d $THEME_DIR && ! -L $THEME_DIR && ! -f $THEME_DIR/$MARKER ]]; then
    local backup
    backup="$THEME_DIR.bak.$(date +%s)"
    mv "$THEME_DIR" "$backup"
    echo "Kept your existing fathom theme at $backup"
  fi
  rm -rf "$THEME_DIR"

  if $link; then
    ln -s "$REPO/theme" "$THEME_DIR"
    echo "Linked $THEME_DIR -> $REPO/theme"
  else
    cp -r "$REPO/theme" "$THEME_DIR"
    git -C "$REPO" rev-parse --short HEAD >"$THEME_DIR/$MARKER" 2>/dev/null || echo unknown >"$THEME_DIR/$MARKER"
    echo "Copied the theme to $THEME_DIR"
  fi

  if $apply; then
    omarchy theme set fathom
    echo "Fathom theme applied. Run ./uninstall.sh to go back to ${current:-your previous theme}."
  fi
}

$skin && install_skin
