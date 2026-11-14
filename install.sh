#!/usr/bin/env bash
# Install Fathom onto an Omarchy machine. Run ./install.sh --help for options.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$HOME/.config/omarchy/themes"
THEME_DIR="$THEMES_DIR/fathom"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fathom"
MARKER=".fathom-install"

skin=false
signin=false
link=false
apply=true

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Parts (with none named, only --skin is installed):
  --skin       The Fathom desktop theme
  --signin     The Fathom sign-in screen (SDDM). Needs your password, since
               it goes in /usr/share/sddm/themes and /etc/sddm.conf.d
  --all        Every part

Options:
  --link       Symlink the desktop theme to this repo instead of copying it,
               so edits here show up after 'omarchy theme set fathom'
  --no-apply   Install the desktop theme without switching to it
  -h, --help   Show this help

Preview the sign-in screen without installing it:
  sddm-greeter-qt6 --test-mode --theme $REPO/signin/fathom
EOF
}

while (($#)); do
  case $1 in
    --skin) skin=true ;;
    --signin) signin=true ;;
    --all)
      skin=true
      signin=true
      ;;
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

# No part named: just the desktop theme, which needs no password.
$skin || $signin || skin=true

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

# Run a command as root: sudo in a terminal, a polkit prompt otherwise.
as_root() {
  if [[ -t 0 ]]; then
    sudo "$@"
  else
    pkexec "$@"
  fi
}

install_signin() {
  if [[ ! -d /usr/share/sddm/themes ]]; then
    echo "install.sh: SDDM is not installed, so there is no sign-in screen to theme." >&2
    return 1
  fi
  as_root bash "$REPO/signin/install-root.sh" install "$REPO/signin/fathom"
  echo "You will see it the next time you sign out. This laptop signs in"
  echo "automatically at boot, so it does not appear when you start up."
}

$skin && install_skin
$signin && install_signin
exit 0
