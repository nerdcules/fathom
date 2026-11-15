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
SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fathom"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
HYPR_BEGIN="-- fathom: begin (added by Fathom's install.sh; uninstall.sh removes it)"
HYPR_END="-- fathom: end"

skin=false
signin=false
player=false
deck=false
mail=false
link=false
apply=true

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Parts (with none named, the ones that need no password: --skin --player --deck --mail):
  --skin       The Fathom desktop theme
  --player     The mini-player: 'fathom-player', its window rules and keys
               (Super+Alt+Y plays the copied link, Super+Ctrl+Y closes it),
               and a bar widget showing what is playing
  --deck       The Command Deck: system, Docker, .NET and AI at a glance
               (Super+Alt+D); its Care page: disk, warnings and updates
               (Super+Alt+C), checked every 3 hours by a systemd user
               timer; and the Start menu (tap Super)
  --mail       New-mail notifications (Outlook.com for now): 'fathom-mail'
               and its service. Then add your account with
               fathom-mail add outlook --client-id <id> (see the README)
  --signin     The Fathom sign-in screen (SDDM). Needs your password, since
               it goes in /usr/share/sddm/themes and /etc/sddm.conf.d
  --all        Every part

Options:
  --link       Symlink the desktop theme, the commands and their Hyprland
               files to this repo instead of copying them, so edits here take
               effect (shell plugins are always copied: Omarchy refuses
               symlinks there)
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
    --deck) deck=true ;;
    --mail) mail=true ;;
    --all)
      skin=true
      signin=true
      player=true
      deck=true
      mail=true
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
if ! $skin && ! $signin && ! $player && ! $deck && ! $mail; then
  skin=true
  player=true
  deck=true
  mail=true
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

# Load ~/.config/hypr/<name>.lua from hyprland.lua, inside one marked block
# that all of Fathom's parts share. Backs hyprland.lua up the first time,
# and takes the part out again if Hyprland reports errors.
hypr_load() {
  local name=$1 src=$2
  local main="$HYPR_DIR/hyprland.lua"
  local line="require(\"hypr.$name\")"
  if [[ ! -f $main ]]; then
    echo "install.sh: $main not found; is this an Omarchy Hyprland setup?" >&2
    return 1
  fi
  place "$src" "$HYPR_DIR/$name.lua"

  if ! grep -qF -- "$HYPR_BEGIN" "$main"; then
    cp "$main" "$main.bak.$(date +%s)"
    # Start on a fresh line, without leaving a blank one behind on uninstall.
    [[ -s $main && -n $(tail -c 1 "$main") ]] && printf '\n' >>"$main"
    printf '%s\n%s\n' "$HYPR_BEGIN" "$HYPR_END" >>"$main"
  fi
  if ! grep -qxF -- "$line" "$main"; then
    sed -i "/^-- fathom: end\$/i $line" "$main"
  fi

  local errors
  errors=$(hypr_errors)
  if [[ -n $errors ]]; then
    echo "install.sh: Hyprland reported config errors, so $name.lua was taken out again:" >&2
    echo "$errors" >&2
    sed -i "/^require(\"hypr\.$name\")\$/d" "$main"
    # Drop the block too if nothing else is in it.
    if [[ $(sed -n "/^-- fathom: begin/,/^-- fathom: end\$/p" "$main" | wc -l) -le 2 ]]; then
      remove_hypr_block
    fi
    rm -f "$HYPR_DIR/$name.lua"
    hypr_errors >/dev/null
    return 1
  fi
}

# Copy a shell plugin into place and turn it on. Always a copy: Omarchy
# refuses plugin folders with symlinks. Extra arguments go to
# `omarchy plugin enable` (bar placement).
install_plugin() {
  local id=$1
  shift
  local plugin="$PLUGINS_DIR/$id"
  rm -rf "$plugin"
  mkdir -p "$PLUGINS_DIR"
  cp -r "$REPO/${id#fathom.}/plugin/$id" "$plugin"
  omarchy plugin validate "$plugin" >/dev/null
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  # The shell finds the new plugin a moment after the rescan, so retry briefly.
  local tries=0
  until omarchy plugin enable "$id" "$@" >/dev/null 2>&1; do
    if ((++tries >= 10)); then
      echo "install.sh: couldn't turn on $id; try: omarchy plugin enable $id" >&2
      return 1
    fi
    sleep 0.5
  done
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
  hypr_load fathom-player "$REPO/player/hypr/fathom-player.lua" || return 1
  install_plugin fathom.player --section centerEnd --index 0

  echo "Mini-player installed. Copy a video link and press Super+Alt+Y."
}

install_deck() {
  local missing=() tool
  for tool in jq curl; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  if ((${#missing[@]})); then
    echo "install.sh: the Command Deck needs: ${missing[*]}" >&2
    return 1
  fi
  command -v docker >/dev/null || echo "Docker isn't installed; the deck's Containers card will say so."

  place "$REPO/deck/bin/fathom-deck" "$BIN_DIR/fathom-deck"
  place "$REPO/care/bin/fathom-care" "$BIN_DIR/fathom-care"
  place "$REPO/start/bin/fathom-start" "$BIN_DIR/fathom-start"
  chmod +x "$REPO/deck/bin/fathom-deck" "$REPO/care/bin/fathom-care" "$REPO/start/bin/fathom-start"
  hypr_load fathom-deck "$REPO/deck/hypr/fathom-deck.lua" || return 1
  install_plugin fathom.deck

  # Care's check, every 3 hours. Copied, not linked: systemd wants real files.
  local units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" unit
  mkdir -p "$units"
  for unit in fathom-care.service fathom-care.timer; do
    cp "$REPO/care/systemd/$unit" "$units/$unit"
  done
  systemctl --user daemon-reload
  systemctl --user enable --now fathom-care.timer >/dev/null 2>&1 ||
    echo "install.sh: couldn't start Care's timer; try: systemctl --user enable --now fathom-care.timer" >&2

  echo "Command Deck installed. Tap Super for Start, Super+Alt+D for the deck, Super+Alt+C for Care."
}

install_mail() {
  local missing=() tool
  for tool in python3 secret-tool busctl xdg-open; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  if ((${#missing[@]})); then
    echo "install.sh: Fathom Mail needs: ${missing[*]}" >&2
    return 1
  fi

  # The command and its Python package. With --link, the command points into
  # this repo and finds the package next to it.
  if $link; then
    rm -rf "$SHARE_DIR/mail"
    place "$REPO/mail/bin/fathom-mail" "$BIN_DIR/fathom-mail"
  else
    rm -rf "$SHARE_DIR/mail"
    mkdir -p "$SHARE_DIR"
    cp -r "$REPO/mail" "$SHARE_DIR/mail"
    rm -rf "$SHARE_DIR/mail/systemd"
    find "$SHARE_DIR/mail" -name __pycache__ -prune -exec rm -rf {} +
    mkdir -p "$BIN_DIR"
    ln -sfn "$SHARE_DIR/mail/bin/fathom-mail" "$BIN_DIR/fathom-mail"
  fi
  chmod +x "$REPO/mail/bin/fathom-mail"

  local units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$units"
  cp "$REPO/mail/systemd/fathom-mail.service" "$units/fathom-mail.service"
  systemctl --user daemon-reload
  systemctl --user enable fathom-mail.service >/dev/null 2>&1 || true
  systemctl --user restart fathom-mail.service >/dev/null 2>&1 || true

  if [[ -s ${XDG_CONFIG_HOME:-$HOME/.config}/fathom/mail.json ]]; then
    echo "Fathom Mail installed and watching your accounts."
  else
    echo "Fathom Mail installed. Add your account: fathom-mail add outlook --client-id <id> (see the README)"
  fi
}

$skin && install_skin
$player && install_player
$deck && install_deck
$mail && install_mail
$signin && install_signin
exit 0
