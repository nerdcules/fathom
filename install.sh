#!/usr/bin/env bash
# Install Fathom onto an Omarchy machine. Run ./install.sh --help for options.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$HOME/.config/omarchy/themes"
THEME_DIR="$THEMES_DIR/fathom"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fathom"
MARKER=".fathom-install"

BIN_DIR="$HOME/.local/bin"
HYPR_DIR="$HOME/.config/hypr"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
HYPR_BEGIN="-- fathom: begin (added by Fathom's install.sh; uninstall.sh removes it)"
HYPR_END="-- fathom: end"

skin=false
signin=false
player=false
link=false
apply=true

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Parts (with none named, the ones that need no password: --skin --player):
  --skin       The Fathom desktop theme
  --player     The mini-player: 'fathom-player', its window rules and keys
               (Super+Alt+Y plays the copied link, Super+Ctrl+Y closes it),
               and a bar widget showing what is playing
  --signin     The Fathom sign-in screen (SDDM). Needs your password, since
               it goes in /usr/share/sddm/themes and /etc/sddm.conf.d
  --all        Every part

Options:
  --link       Symlink the desktop theme, fathom-player and its Hyprland file
               to this repo instead of copying them, so edits here take effect
               (the bar widget is always copied: Omarchy refuses symlinks there)
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
    --player) player=true ;;
    --all)
      skin=true
      signin=true
      player=true
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

# No part named: the parts that need no password.
if ! $skin && ! $signin && ! $player; then
  skin=true
  player=true
fi

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

# Copy a file into place, or link it to the repo with --link.
place() {
  local src=$1 dest=$2
  mkdir -p "$(dirname "$dest")"
  rm -f "$dest"
  if $link; then
    ln -s "$src" "$dest"
  else
    cp "$src" "$dest"
  fi
}

hypr_errors() {
  hyprctl reload >/dev/null 2>&1 || true
  hyprctl configerrors 2>/dev/null | sed '/^[[:space:]]*$/d'
}

remove_hypr_block() {
  local main="$HYPR_DIR/hyprland.lua"
  [[ -f $main ]] && sed -i "/^-- fathom: begin/,/^-- fathom: end\$/d" "$main"
}

install_player() {
  local missing=() tool
  for tool in mpv yt-dlp socat jq wl-paste; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  if ((${#missing[@]})); then
    echo "install.sh: the mini-player needs: ${missing[*]}" >&2
    echo "  Install them with: omarchy pkg add mpv yt-dlp socat jq wl-clipboard" >&2
    return 1
  fi

  place "$REPO/player/bin/fathom-player" "$BIN_DIR/fathom-player"
  chmod +x "$REPO/player/bin/fathom-player"
  place "$REPO/player/hypr/fathom-player.lua" "$HYPR_DIR/fathom-player.lua"

  # Load the rules and keys from hyprland.lua, once, keeping a backup.
  local main="$HYPR_DIR/hyprland.lua"
  if [[ ! -f $main ]]; then
    echo "install.sh: $main not found; is this an Omarchy Hyprland setup?" >&2
    return 1
  fi
  if ! grep -qF -- "$HYPR_BEGIN" "$main"; then
    cp "$main" "$main.bak.$(date +%s)"
    # Start on a fresh line, without leaving a blank one behind on uninstall.
    [[ -s $main && -n $(tail -c 1 "$main") ]] && printf '\n' >>"$main"
    printf '%s\nrequire("hypr.fathom-player")\n%s\n' "$HYPR_BEGIN" "$HYPR_END" >>"$main"
  fi

  local errors
  errors=$(hypr_errors)
  if [[ -n $errors ]]; then
    echo "install.sh: Hyprland reported config errors, so the player's rules were taken out again:" >&2
    echo "$errors" >&2
    remove_hypr_block
    rm -f "$HYPR_DIR/fathom-player.lua"
    hypr_errors >/dev/null
    return 1
  fi

  # The bar widget. Always a copy: Omarchy refuses plugin folders with symlinks.
  local plugin="$PLUGINS_DIR/fathom.player"
  rm -rf "$plugin"
  mkdir -p "$PLUGINS_DIR"
  cp -r "$REPO/player/plugin/fathom.player" "$plugin"
  omarchy plugin validate "$plugin" >/dev/null
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  # The shell finds the new plugin a moment after the rescan, so retry briefly.
  local tries=0
  until omarchy plugin enable fathom.player --section centerEnd --index 0 >/dev/null 2>&1; do
    if ((++tries >= 10)); then
      echo "install.sh: couldn't add the mini-player to the bar; try: omarchy plugin enable fathom.player" >&2
      break
    fi
    sleep 0.5
  done

  echo "Mini-player installed. Copy a video link and press Super+Alt+Y."
}

$skin && install_skin
$player && install_player
$signin && install_signin
exit 0
