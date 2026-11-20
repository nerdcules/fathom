#!/usr/bin/env bash
# Install Fathom onto an Omarchy machine. Run ./install.sh --help for options.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$HOME/.config/omarchy/themes"
THEME_DIR="$THEMES_DIR/fathom"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fathom"
# Copies being checked, and what they replace, until a part is in place.
STAGE="$STATE_DIR/staging"
# The parts that finished installing, one per line.
INSTALLED="$STATE_DIR/installed"
MARKER=".fathom-install"

BIN_DIR="$HOME/.local/bin"
HYPR_DIR="$HOME/.config/hypr"
SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fathom"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
HYPR_BEGIN="-- fathom: begin (added by Fathom's install.sh; uninstall.sh removes it)"
HYPR_END="-- fathom: end"
# Read only, for Pulse's firewall rule; tests point it at a scratch folder.
UFW_DIR="${FATHOM_UFW_DIR:-/etc/ufw}"

skin=false
signin=false
player=false
deck=false
desk=false
screensaver=false
mail=false
sentinel=false
pulse=false
crumbs=false
phone=false
opensnitch=false
link=false
apply=true
restart_shell=false

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Parts (with none named, the ones that need no password: --skin --player --deck --desk --mail):
  --skin       The Fathom desktop theme, and 'fathom-look', which changes
               its look (the deck's Personalise page uses it)
  --player     The mini-player: 'fathom-player', its window rules and keys
               (Super+Alt+Y plays the copied link, Super+Ctrl+Y closes it),
               and a bar widget showing what is playing
  --deck       The Command Deck: system, Docker, .NET and AI at a glance
               (Super+Alt+D); its Care page: disk, warnings and updates
               (Super+Alt+C), checked every 3 hours by a systemd user
               timer; Personalise, for Fathom's look (Super+Alt+I);
               and the Start menu (tap Super)
  --desk       Windows-style window handling: Alt+Tab with window previews,
               Task view (Super+Tab, in place of Omarchy's next workspace),
               Snap layouts (Super+Z) and Quick settings (Super+Alt+A)
  --screensaver
               Blueprint, software patterns drawn as blueprints, as the
               screensaver: built here (needs base-devel and Qt 6, both in
               Omarchy), with Omarchy's idle service cloned as fathom.idle
               to start it. Pick it, or Omarchy's own, on Personalise
  --mail       New-mail notifications (Outlook.com for now): 'fathom-mail'
               and its service. Then add your account with
               fathom-mail add outlook --client-id <id> (see the README)
  --sentinel   Sentinel: watches firewall blocks, sign-ins, USB storage, new
               devices on your network and system files (Super+Alt+X).
               Needs your password for its daily file check and firewall
               buttons
  --pulse      Pulse: a small OpenTelemetry collector that maps what calls
               what in your stack, on the deck's fourth page (Super+Alt+P).
               Needs python-opentelemetry-proto, python-grpcio and
               python-protobuf. Asks for your password once if the firewall
               is on and Docker is installed, to let containers reach it
  --phone      The laptop side of Fathom for Android: a service the phone
               pairs with (fathom-phone pair) and reads the deck from, on
               port 4920. Needs your password for the firewall rule that
               lets your home network and Tailscale reach it
  --crumbs     Crumbs: the cookies every browser here keeps, which are
               trackers and which sites led to them (Super+Alt+O), and
               blocking them. Needs your password for the helper that
               writes the browsers' cookie rules
  --signin     The Fathom sign-in screen (SDDM). Needs your password, since
               it goes in /usr/share/sddm/themes and /etc/sddm.conf.d
  --all        Every part (OpenSnitch only if asked for)

Options:
  --opensnitch With --sentinel: also install OpenSnitch, which asks the first
               time each app connects somewhere new
  --link       Symlink the commands, their Hyprland files and the theme
               fathom-look builds from to this repo instead of copying them,
               so edits here take effect (after 'fathom-look apply' for the
               theme; shell plugins are always copied: Omarchy refuses
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
    --desk) desk=true ;;
    --screensaver) screensaver=true ;;
    --mail) mail=true ;;
    --sentinel) sentinel=true ;;
    --pulse) pulse=true ;;
    --crumbs) crumbs=true ;;
    --phone) phone=true ;;
    --opensnitch) opensnitch=true ;;
    --all)
      skin=true
      signin=true
      player=true
      deck=true
      desk=true
      screensaver=true
      mail=true
      sentinel=true
      pulse=true
      crumbs=true
      phone=true
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
if $opensnitch && ! $sentinel; then
  echo "install.sh: --opensnitch goes with --sentinel" >&2
  exit 2
fi

if ! $skin && ! $signin && ! $player && ! $deck && ! $desk && ! $screensaver && ! $mail && ! $sentinel && ! $pulse && ! $crumbs && ! $phone; then
  skin=true
  player=true
  deck=true
  desk=true
  mail=true
fi

if ! command -v omarchy >/dev/null; then
  echo "install.sh: Fathom needs Omarchy (https://omarchy.org)." >&2
  exit 1
fi

# Put back what install_skin moved aside, after a failed build or apply.
skin_restore() {
  local base=$1 backup=$2
  rm -rf "$base"
  if [[ -e $STAGE/theme-base || -L $STAGE/theme-base ]]; then
    mv "$STAGE/theme-base" "$base"
  fi
  # Only a folder Fathom built (or an older install's link) is taken out.
  if [[ -L $THEME_DIR || -f $THEME_DIR/$MARKER ]]; then
    rm -rf "$THEME_DIR"
  fi
  if [[ -e $STAGE/theme-dir || -L $STAGE/theme-dir ]]; then
    mv "$STAGE/theme-dir" "$THEME_DIR"
  fi
  if [[ -n $backup ]]; then
    mv "$backup" "$THEME_DIR"
  fi
}

install_skin() {
  mkdir -p "$THEMES_DIR" "$STATE_DIR" "$SHARE_DIR" "$STAGE"

  # Remember the theme to go back to on uninstall, unless Fathom is already on.
  local current
  current=$(omarchy theme current 2>/dev/null || true)
  if [[ -n $current && ${current,,} != fathom ]]; then
    printf '%s\n' "$current" >"$STATE_DIR/previous-theme"
  fi

  # Fathom's theme as shipped goes in ~/.local/share/fathom/theme (linked to
  # the repo with --link). fathom-look builds the folder Omarchy reads from
  # it, with your look from Personalise (~/.config/fathom/look.json). The
  # theme installed now, its built folder and fathom-look stay until the new
  # theme has built and, unless --no-apply, Omarchy has switched to it.
  local base="$SHARE_DIR/theme" backup=""
  rm -rf "$STAGE/theme-base" "$STAGE/theme-dir"
  if [[ -e $base || -L $base ]]; then
    mv "$base" "$STAGE/theme-base"
  fi
  if $link; then
    ln -s "$REPO/theme" "$base"
  else
    cp -r "$REPO/theme" "$base"
  fi
  if [[ -L $THEME_DIR || -f $THEME_DIR/$MARKER ]]; then
    cp -a "$THEME_DIR" "$STAGE/theme-dir"
  elif [[ -d $THEME_DIR ]]; then
    # A fathom theme folder this script did not make is the user's: keep it.
    backup="$THEME_DIR.bak.$(date +%s)"
    mv "$THEME_DIR" "$backup"
  fi

  # The new fathom-look builds (beside the old folder, swapped in whole).
  chmod +x "$REPO/look/bin/fathom-look"
  if ! "$REPO/look/bin/fathom-look" build >/dev/null; then
    skin_restore "$base" "$backup"
    echo "install.sh: Fathom's theme didn't build, so the theme you had is back as it was." >&2
    return 1
  fi

  if $apply && ! omarchy theme set fathom; then
    skin_restore "$base" "$backup"
    if [[ -n $current ]] && omarchy theme set "$current"; then
      echo "install.sh: Omarchy couldn't switch to Fathom's theme, so $current is back as it was." >&2
    else
      echo "install.sh: Omarchy couldn't switch to Fathom's theme; the theme folders are back as they were." >&2
      [[ -n $current ]] && echo "  Switch back with: omarchy theme set \"$current\"" >&2
    fi
    return 1
  fi
  rm -rf "$STAGE/theme-base" "$STAGE/theme-dir"
  [[ -n $backup ]] && echo "Kept your existing fathom theme at $backup"
  place "$REPO/look/bin/fathom-look" "$BIN_DIR/fathom-look"

  if $apply; then
    # Fathom's bar and popups are glass, which needs the glassy bar: Hyprland
    # blurs behind it (and turns blur on desktop-wide). Remember the bar's
    # own look to go back to on uninstall.
    local bar
    bar=$(omarchy bar background 2>/dev/null || true)
    if [[ $bar == opaque || $bar == none ]]; then
      printf '%s\n' "$bar" >"$STATE_DIR/previous-bar"
      omarchy bar background glassy >/dev/null ||
        echo "install.sh: couldn't make the bar glassy; try: omarchy bar background glassy" >&2
    fi
    local previous=""
    [[ -s $STATE_DIR/previous-theme ]] && previous=$(<"$STATE_DIR/previous-theme")
    echo "Fathom theme applied. Run ./uninstall.sh to go back to ${previous:-your previous theme}."
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
  # A copy with this install's version in it; install-root.sh copies that.
  local theme
  theme=$(mktemp -d)/fathom
  cp -rL "$REPO/signin/fathom" "$theme"
  write_version_js "$theme/Version.js"
  as_root bash "$REPO/signin/install-root.sh" install "$theme"
  rm -rf "$(dirname "$theme")"
  # SDDM reads /etc/sddm.conf, then sddm.conf.d in name order; the last
  # [Autologin] User= wins.
  local auto="" conf files=()
  for conf in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
    [[ -f $conf ]] && files+=("$conf")
  done
  if ((${#files[@]})); then
    auto=$(awk 'FNR==1{s=0} /^\[/{s=($0=="[Autologin]")} s && /^User=/{u=substr($0,6)} END{print u}' "${files[@]}")
  fi
  if [[ -n $auto && $auto == "$USER" ]]; then
    echo "You will see it the next time you sign out. This machine signs you in"
    echo "automatically at boot, so it does not appear when you start up."
  else
    echo "You will see it the next time you start up or sign out."
  fi
}

# Fathom's version, from git: the release tag, the build number (commits
# since that release) and the commit, e.g. "v0.1.0 · build 12 · 0847b57".
# Sets VERSION, BUILD, COMMIT, DIRTY and VERSION_TEXT.
fathom_version() {
  VERSION="" BUILD=-1 COMMIT="" DIRTY=false VERSION_TEXT="version unknown (not a git checkout)"
  command -v git >/dev/null && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || return 0
  local desc
  COMMIT=$(git -C "$REPO" rev-parse --short=7 HEAD)
  [[ -n $(git -C "$REPO" status --porcelain --untracked-files=no) ]] && DIRTY=true
  desc=$(git -C "$REPO" describe --tags --long --abbrev=7 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)
  if [[ $desc =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-g[0-9a-f]+$ ]]; then
    VERSION=${BASH_REMATCH[1]} BUILD=${BASH_REMATCH[2]}
  else
    VERSION=0.0.0 BUILD=$(git -C "$REPO" rev-list --count HEAD)  # no release yet
  fi
  VERSION_TEXT="v$VERSION · build $BUILD · $COMMIT"
  $DIRTY && VERSION_TEXT+=" · with local changes"
  return 0
}

# Writes the version into an installed copy's Version.js.
write_version_js() {
  local dest=$1
  cat >"$dest" <<EOF
.pragma library
// Written by install.sh: the version of Fathom installed here.
var version = "$VERSION"
var build = $BUILD
var commit = "$COMMIT"
var dirty = $DIRTY
var text = "$VERSION_TEXT"
EOF
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

# Copy a shell plugin into the staging folder and check it there, before
# anything of its part changes. Always a copy: Omarchy refuses plugin
# folders with symlinks.
stage_plugin() {
  local id=$1
  rm -rf "${STAGE:?}/$id"
  mkdir -p "$STAGE"
  cp -r "$REPO/${id#fathom.}/plugin/$id" "$STAGE/$id"
  [[ -f $STAGE/$id/Version.js ]] && write_version_js "$STAGE/$id/Version.js"
  if ! omarchy plugin validate "$STAGE/$id" >/dev/null; then
    rm -rf "${STAGE:?}/$id"
    echo "install.sh: Omarchy found a problem with the new $id (above); the one you had is unchanged." >&2
    return 1
  fi
}

# Swap the staged plugin in and turn it on; if Omarchy won't turn it on,
# put the one that was there back. Extra arguments go to
# `omarchy plugin enable` (bar placement).
install_plugin() {
  local id=$1
  shift
  local plugin="$PLUGINS_DIR/$id" prev="$STAGE/$id.prev"
  [[ -d $STAGE/$id ]] || stage_plugin "$id" || return 1
  rm -rf "$prev"
  mkdir -p "$PLUGINS_DIR"
  if [[ -d $plugin ]]; then
    # Updating a plugin the shell already loaded: the running shell can
    # keep parts of the old version (seen with fathom.deck's Skin.qml), so
    # restart it once at the end.
    restart_shell=true
    mv "$plugin" "$prev"
  fi
  mv "$STAGE/$id" "$plugin"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  # The shell finds the new plugin a moment after the rescan, so retry briefly.
  local tries=0
  until omarchy plugin enable "$id" "$@" >/dev/null 2>&1; do
    if ((++tries >= 10)); then
      rm -rf "$plugin"
      if [[ -d $prev ]]; then
        mv "$prev" "$plugin"
        echo "install.sh: couldn't turn on the new $id, so the one you had is back; try: omarchy plugin enable $id" >&2
      else
        echo "install.sh: couldn't turn on $id; try: ./install.sh again, or omarchy plugin enable $id" >&2
      fi
      omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
      return 1
    fi
    sleep 0.5
  done
  rm -rf "$prev"
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
  stage_plugin fathom.player || return 1

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
  stage_plugin fathom.deck || return 1

  place "$REPO/deck/bin/fathom-deck" "$BIN_DIR/fathom-deck"
  place "$REPO/care/bin/fathom-care" "$BIN_DIR/fathom-care"
  place "$REPO/start/bin/fathom-start" "$BIN_DIR/fathom-start"
  chmod +x "$REPO/deck/bin/fathom-deck" "$REPO/care/bin/fathom-care" "$REPO/start/bin/fathom-start"
  hypr_load fathom-deck "$REPO/deck/hypr/fathom-deck.lua" || return 1
  install_plugin fathom.deck --section left

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

install_desk() {
  local missing=() tool
  for tool in jq hyprctl nmcli; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  if ((${#missing[@]})); then
    echo "install.sh: the desk needs: ${missing[*]}" >&2
    return 1
  fi
  stage_plugin fathom.desk || return 1

  place "$REPO/desk/bin/fathom-desk" "$BIN_DIR/fathom-desk"
  chmod +x "$REPO/desk/bin/fathom-desk"
  hypr_load fathom-desk "$REPO/desk/hypr/fathom-desk.lua" || return 1
  install_plugin fathom.desk

  echo "Desk installed. Alt+Tab switches windows, Super+Tab shows Task view, Super+Z snaps a window, Super+Alt+A opens Quick settings."
}

# Omarchy's idle service, copied the way `omarchy plugin clone` copies it,
# as fathom.idle. One line changes: the one that starts the screensaver runs
# fathom-screensaver instead of omarchy-launch-screensaver. If Omarchy has
# changed that line, nothing is staged and the stock service stays.
stage_idle() {
  local src service="$STAGE/fathom.idle/Service.qml"
  local stock='|| omarchy-launch-screensaver")' ours='|| $HOME/.local/bin/fathom-screensaver")'
  src=$(omarchy-plugin-catalog 2>/dev/null | jq -r '.[] | select(.firstParty and .id == "omarchy.idle") | .sourceDir // empty' | head -n 1)
  if [[ -z $src || ! -f $src/Service.qml ]]; then
    echo "install.sh: couldn't find Omarchy's idle service (omarchy.idle) to clone." >&2
    return 1
  fi
  rm -rf "${STAGE:?}/fathom.idle"
  mkdir -p "$STAGE/fathom.idle"
  cp -aL "$src/." "$STAGE/fathom.idle/"
  if [[ $(grep -cF -- "$stock" "$service") != 1 ]]; then
    rm -rf "${STAGE:?}/fathom.idle"
    echo "install.sh: Omarchy's idle service no longer starts the screensaver the way Fathom expects;" >&2
    echo "  its own screensaver is unchanged. Please report this with your Omarchy version." >&2
    return 1
  fi
  STOCK=$stock OURS=$ours perl -0pi -e 's/\Q$ENV{STOCK}\E/$ENV{OURS}/' "$service"
  jq '.id = "fathom.idle" | .name = "Fathom Idle"
    | .description = "Omarchy'"'"'s idle service, starting Fathom'"'"'s screensaver (fathom-screensaver)."
    | .omarchy = ((if (.omarchy | type) == "object" then .omarchy else {} end) + {clonedFrom: "omarchy.idle"})
    | del(.omarchy.clonePaths)' "$STAGE/fathom.idle/manifest.json" >"$STAGE/fathom.idle/manifest.json.new"
  mv "$STAGE/fathom.idle/manifest.json.new" "$STAGE/fathom.idle/manifest.json"
  if ! omarchy plugin validate "$STAGE/fathom.idle" >/dev/null; then
    rm -rf "${STAGE:?}/fathom.idle"
    echo "install.sh: Omarchy found a problem with fathom.idle (above); its own idle service is unchanged." >&2
    return 1
  fi
}

# An idle service of your own: a clone of Omarchy's (by its manifest) that
# shell.json turns on. Read from the files, not from the running shell: on
# this laptop, asking the shell (`omarchy-plugin-list`) just after --skin
# had switched the theme found no such service, and the install switched
# the user's own off.
own_idle_service() {
  local config="$HOME/.config/omarchy/shell.json" id
  [[ -s $config ]] || return 0
  while IFS= read -r id; do
    [[ $id =~ ^[A-Za-z0-9_.-]+$ && $id != fathom.idle && $id != omarchy.idle ]] || continue
    if [[ $(jq -r '.omarchy.clonedFrom // empty' "$PLUGINS_DIR/$id/manifest.json" 2>/dev/null) == omarchy.idle ]]; then
      echo "$id"
      return 0
    fi
  done < <(jq -r '.plugins[]? | (if type == "object" then .id else . end) | strings' "$config" 2>/dev/null)
}

install_screensaver() {
  local missing=() tool
  for tool in qmake6 make g++ jq socat hyprctl perl; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  if ((${#missing[@]})); then
    echo "install.sh: the screensaver needs: ${missing[*]}" >&2
    echo "  Install them with: omarchy pkg add base-devel qt6-base qt6-declarative socat" >&2
    return 1
  fi

  # Build Blueprint in the stage; the one you had stays until this one has
  # built and passed its own check of the diagrams.
  local build="$STAGE/blueprint-build" dest="$SHARE_DIR/blueprint"
  rm -rf "$build"
  mkdir -p "$build"
  echo "Building Blueprint..."
  if ! (cd "$build" && qmake6 "$REPO/screensaver/blueprint/blueprint.pro" >"$build/build.log" 2>&1 &&
    make -j"$(nproc)" >>"$build/build.log" 2>&1); then
    tail -n 20 "$build/build.log" >&2
    echo "install.sh: Blueprint didn't build (above); the screensaver you had is unchanged." >&2
    return 1
  fi
  if ! QT_QPA_PLATFORM=offscreen "$build/blueprint" check >/dev/null 2>&1; then
    echo "install.sh: the new Blueprint failed its check of the diagrams; the screensaver you had is unchanged." >&2
    return 1
  fi
  mkdir -p "$dest"
  install -m 755 "$build/blueprint" "$dest/blueprint.new"
  mv "$dest/blueprint.new" "$dest/blueprint"
  rm -rf "$build"

  place "$REPO/screensaver/bin/fathom-screensaver" "$BIN_DIR/fathom-screensaver"
  chmod +x "$REPO/screensaver/bin/fathom-screensaver"

  # An idle service of your own (another clone of Omarchy's) is left alone.
  local other
  other=$(own_idle_service)
  if [[ -n $other ]]; then
    echo "Blueprint is installed, but your own idle service ($other) starts the screensaver, so Fathom's isn't switched on."
    echo "  To use Fathom's: omarchy plugin disable $other, then $REPO/install.sh --screensaver"
    return 0
  fi
  stage_idle || return 1
  install_plugin fathom.idle
  # Omarchy's own idle service stays loaded beside it until the shell
  # restarts (seen in the test VM: its handlers kept answering).
  restart_shell=true

  echo "Screensaver installed: Blueprint. Personalise (Super+Alt+I) picks it or Omarchy's, sets when it starts, and previews it."
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

install_sentinel() {
  local missing=() tool
  for tool in python3 ufw jq busctl iw ip; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  if ((${#missing[@]})); then
    echo "install.sh: Sentinel needs: ${missing[*]}" >&2
    return 1
  fi

  # The watcher runs as you.
  if $link; then
    rm -rf "$SHARE_DIR/sentinel"
    place "$REPO/sentinel/bin/fathom-sentinel" "$BIN_DIR/fathom-sentinel"
  else
    rm -rf "$SHARE_DIR/sentinel"
    mkdir -p "$SHARE_DIR"
    mkdir -p "$SHARE_DIR/sentinel"
    cp -r "$REPO/sentinel/bin" "$REPO/sentinel/fathom_sentinel" "$SHARE_DIR/sentinel/"
    find "$SHARE_DIR/sentinel" -name __pycache__ -prune -exec rm -rf {} +
    mkdir -p "$BIN_DIR"
    ln -sfn "$SHARE_DIR/sentinel/bin/fathom-sentinel" "$BIN_DIR/fathom-sentinel"
  fi
  chmod +x "$REPO/sentinel/bin/fathom-sentinel"
  hypr_load fathom-sentinel "$REPO/sentinel/hypr/fathom-sentinel.lua" || return 1

  local units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$units"
  cp "$REPO/sentinel/systemd/fathom-sentinel.service" "$units/fathom-sentinel.service"
  systemctl --user daemon-reload
  systemctl --user enable fathom-sentinel.service >/dev/null 2>&1 || true
  systemctl --user restart fathom-sentinel.service

  # The daily file check, the firewall buttons and OpenSnitch need root.
  local args=(install "$REPO/sentinel")
  $opensnitch && args+=(--opensnitch)
  as_root bash "$REPO/sentinel/install-root.sh" "${args[@]}"
  if $opensnitch && ! pgrep -x opensnitch-ui >/dev/null; then
    setsid uwsm-app -- opensnitch-ui >/dev/null 2>&1 &
  fi

  echo "Sentinel is watching. Press Super+Alt+X to see it."
}

# Whose is the ufw rule letting containers reach Pulse at this address:
# "fathom" (it has Fathom's comment), "yours" (one that matches apart from
# its action or comment), or nothing. ufw's rule files are world-readable.
pulse_rule_owner() {
  local bridge=$1 hex line owner=""
  hex=$(printf fathom-pulse | od -An -tx1 | tr -d ' \n')
  while read -r line; do
    if [[ $line == "### tuple ### allow tcp 4317,4318 $bridge any 172.16.0.0/12 in comment=$hex" ]]; then
      owner=${owner:-fathom}
    else
      owner=yours
    fi
  done < <(grep -E "^### tuple ### [^ ]+ tcp 4317,4318 ${bridge//./\\.} any 172\\.16\\.0\\.0/12 in( |\$)" \
    "$UFW_DIR/user.rules" 2>/dev/null || true)
  echo "$owner"
}

install_pulse() {
  if ! python3 -I -c 'import grpc, google.protobuf, opentelemetry.proto' 2>/dev/null; then
    echo "install.sh: Pulse needs python-opentelemetry-proto, python-grpcio and python-protobuf." >&2
    echo "  Install them with: omarchy pkg add python-opentelemetry-proto python-grpcio python-protobuf" >&2
    return 1
  fi

  if $link; then
    rm -rf "$SHARE_DIR/pulse"
    place "$REPO/pulse/bin/fathom-pulse" "$BIN_DIR/fathom-pulse"
  else
    rm -rf "$SHARE_DIR/pulse"
    mkdir -p "$SHARE_DIR/pulse"
    cp -r "$REPO/pulse/bin" "$REPO/pulse/fathom_pulse" "$SHARE_DIR/pulse/"
    find "$SHARE_DIR/pulse" -name __pycache__ -prune -exec rm -rf {} +
    mkdir -p "$BIN_DIR"
    ln -sfn "$SHARE_DIR/pulse/bin/fathom-pulse" "$BIN_DIR/fathom-pulse"
  fi
  chmod +x "$REPO/pulse/bin/fathom-pulse"
  hypr_load fathom-pulse "$REPO/pulse/hypr/fathom-pulse.lua" || return 1

  local units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$units"
  cp "$REPO/pulse/systemd/fathom-pulse.service" "$units/fathom-pulse.service"
  systemctl --user daemon-reload
  systemctl --user enable fathom-pulse.service >/dev/null 2>&1 || true
  systemctl --user restart fathom-pulse.service

  # Containers reach Pulse on Docker's bridge address, and a firewall that
  # denies incoming connections (Omarchy's ufw) blocks them there. Allow
  # only Docker's private ranges, only to that address, only these ports.
  local bridge owner
  bridge=$(ip -j -4 addr show docker0 2>/dev/null | jq -r '.[0].addr_info[0].local // empty' 2>/dev/null || true)
  if [[ -n $bridge ]] && command -v ufw >/dev/null; then
    owner=$(pulse_rule_owner "$bridge")
    if [[ $owner == yours ]]; then
      # ufw would turn your rule into Fathom's (its comment and action)
      # instead of adding one, and uninstall.sh would then remove it.
      echo "install.sh: a firewall rule of yours already decides whether containers reach Pulse's ports; Fathom leaves it and adds none."
    elif [[ $owner != fathom ]]; then
      mkdir -p "$STATE_DIR"
      printf '%s\n' "$bridge" >"$STATE_DIR/pulse-bridge"
      as_root ufw allow proto tcp from 172.16.0.0/12 to "$bridge" port 4317,4318 comment fathom-pulse >/dev/null ||
        echo "install.sh: couldn't let containers through the firewall; they can't reach Pulse until you do (see the README)." >&2
    fi
  fi

  echo "Pulse is listening. Point an app's OpenTelemetry exporter at it (see the README), then press Super+Alt+P."
}

# Let the phone reach fathom-phone on port 4920: from the private address
# ranges home networks use, and on Tailscale's interface if there is one.
# A matching rule already there is left alone (ufw would otherwise turn a
# rule of yours into Fathom's); Fathom's own are tagged fathom-phone. All
# the rules needed go in one root call, so one password prompt.
phone_firewall() {
  command -v ufw >/dev/null || return 0
  local hex src line cmds=()
  hex=$(printf fathom-phone | od -An -tx1 | tr -d ' \n')
  for src in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
    line=$(grep -E "^### tuple ### [^ ]+ tcp 4920 0\.0\.0\.0/0 any ${src//./\\.} in( |\$)" \
      "$UFW_DIR/user.rules" 2>/dev/null || true)
    if [[ -z $line ]]; then
      cmds+=("ufw allow proto tcp from $src to any port 4920 comment fathom-phone")
    elif [[ $line != *"comment=$hex" ]]; then
      echo "install.sh: a firewall rule of yours for port 4920 from $src is there already; Fathom leaves it."
    fi
  done
  if ip link show tailscale0 >/dev/null 2>&1; then
    line=$(grep -E "^### tuple ### [^ ]+ tcp 4920 0\.0\.0\.0/0 any 0\.0\.0\.0/0 in_tailscale0( |\$)" \
      "$UFW_DIR/user.rules" 2>/dev/null || true)
    if [[ -z $line ]]; then
      cmds+=("ufw allow in on tailscale0 to any port 4920 proto tcp comment fathom-phone")
    elif [[ $line != *"comment=$hex" ]]; then
      echo "install.sh: a firewall rule of yours for port 4920 on Tailscale is there already; Fathom leaves it."
    fi
  fi
  ((${#cmds[@]})) || return 0
  local joined
  joined=$(printf '%s >/dev/null && ' "${cmds[@]}")
  as_root bash -c "${joined% && }"
}

install_phone() {
  local missing=() tool
  for tool in python3 openssl ip; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  if ((${#missing[@]})); then
    echo "install.sh: the phone service needs: ${missing[*]}" >&2
    return 1
  fi
  place "$REPO/phone/bin/fathom-phone" "$BIN_DIR/fathom-phone"
  chmod +x "$REPO/phone/bin/fathom-phone"
  local units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$units"
  cp "$REPO/phone/systemd/fathom-phone.service" "$units/fathom-phone.service"
  systemctl --user daemon-reload
  systemctl --user enable fathom-phone.service >/dev/null 2>&1 || true
  systemctl --user restart fathom-phone.service
  phone_firewall ||
    echo "install.sh: couldn't open port 4920 in the firewall; the phone can't reach Fathom until it is (see the README)." >&2
  echo "Phone service installed. Pair your phone: fathom-phone pair"
}

install_crumbs() {
  command -v python3 >/dev/null || { echo "install.sh: Crumbs needs python3" >&2; return 1; }
  place "$REPO/crumbs/bin/fathom-crumbs" "$BIN_DIR/fathom-crumbs"
  chmod +x "$REPO/crumbs/bin/fathom-crumbs"
  hypr_load fathom-crumbs "$REPO/crumbs/hypr/fathom-crumbs.lua" || return 1
  # The helper that writes the browsers' cookie rules runs as root, so it's
  # copied root-owned, never linked.
  as_root bash "$REPO/crumbs/install-root.sh" install "$REPO/crumbs" ||
    echo "install.sh: Crumbs shows your cookies, but can't block until this runs: sudo bash $REPO/crumbs/install-root.sh install $REPO/crumbs" >&2
  echo "Crumbs installed. Press Super+Alt+O to see your browsers' cookies."
}

# Put back whatever an unfinished install moved aside: the theme and the
# plugins as they were before it. Copies that were only being checked go.
# Runs when a part fails, and first thing, in case an install was killed.
restore_staged() {
  [[ -d $STAGE ]] || return 0
  local prev id
  if [[ -e $STAGE/theme-base || -L $STAGE/theme-base ]]; then
    rm -rf "$SHARE_DIR/theme"
    mv "$STAGE/theme-base" "$SHARE_DIR/theme"
  fi
  if [[ -e $STAGE/theme-dir || -L $STAGE/theme-dir ]] &&
    [[ -L $THEME_DIR || -f $THEME_DIR/$MARKER || ! -e $THEME_DIR ]]; then
    rm -rf "$THEME_DIR"
    mv "$STAGE/theme-dir" "$THEME_DIR"
  fi
  for prev in "$STAGE"/*.prev; do
    [[ -d $prev ]] || continue
    id=$(basename "$prev" .prev)
    rm -rf "${PLUGINS_DIR:?}/$id"
    mv "$prev" "$PLUGINS_DIR/$id"
  done
  rm -rf "$STAGE"
}

# The parts asked for, in the order they're installed.
parts=()
for part in skin player deck desk screensaver mail sentinel pulse crumbs phone signin; do
  ${!part} && parts+=("$part")
done
done_parts=()
current_part=""

# Each part that finishes is added to $INSTALLED, so you can see what is in
# place after an install that stopped. If a part fails, say what finished,
# what didn't, and the command that carries on from there.
report_failure() {
  local code=$?
  [[ -n $current_part ]] || return 0
  restore_staged
  local rest=() flags=() p seen=false
  for p in "${parts[@]}"; do
    [[ $p == "$current_part" ]] && seen=true
    $seen && rest+=("--$p")
  done
  $link && flags+=(--link)
  $apply || flags+=(--no-apply)
  $opensnitch && [[ " ${rest[*]} " == *" --sentinel "* ]] && flags+=(--opensnitch)
  {
    echo
    echo "install.sh: --$current_part failed (see above), so the install stopped there."
    if ((${#done_parts[@]})); then
      echo "  Installed in this run: ${done_parts[*]/#/--}"
    else
      echo "  Nothing was installed in this run."
    fi
    echo "  Not done in this run: ${rest[*]}"
    echo "  A plugin or theme that didn't validate, build or switch on was put back as it"
    echo "  was; other files of --$current_part may be in place. Parts that finished, in any"
    echo "  run, are listed in $INSTALLED."
    echo "To carry on once the problem is fixed (finished parts are kept; rerunning a part is safe):"
    echo "  $REPO/install.sh ${rest[*]}${flags[*]:+ ${flags[*]}}"
    echo "To remove everything Fathom installed instead: $REPO/uninstall.sh"
  } >&2
  exit "$code"
}
trap report_failure EXIT

# Where this install came from, for fathom-update: the clone, its commit and
# branch, the options and every part installed so far.
record_source() {
  local commit="" branch="" dirty=false
  if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    commit=$(git -C "$REPO" rev-parse HEAD)
    branch=$(git -C "$REPO" symbolic-ref --short -q HEAD || true)
    [[ -n $(git -C "$REPO" status --porcelain --untracked-files=no) ]] && dirty=true
  fi
  python3 -I - "$STATE_DIR/source" "$REPO" "$commit" "$branch" "$dirty" "$link" "$apply" "$opensnitch" "$INSTALLED" \
    "$VERSION" "$BUILD" "$VERSION_TEXT" <<'PY'
import json, os, sys, time
out, repo, commit, branch, dirty, link, apply_, snitch, installed, version, build, version_text = sys.argv[1:]
try:
    parts = [l.strip() for l in open(installed) if l.strip()]
except OSError:
    parts = []
data = {"repo": repo, "commit": commit or None, "branch": branch or None, "dirty": dirty == "true",
        "link": link == "true", "apply": apply_ == "true", "opensnitch": snitch == "true",
        "parts": parts, "version": version or None, "build": int(build) if int(build) >= 0 else None,
        "versionText": version_text}
with open(out + ".new", "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(out + ".new", out)
PY
}

mkdir -p "$STATE_DIR"
fathom_version
restore_staged
# fathom-update comes with every install, whichever parts.
place "$REPO/update/bin/fathom-update" "$BIN_DIR/fathom-update"
chmod +x "$REPO/update/bin/fathom-update"
for part in "${parts[@]}"; do
  current_part=$part
  "install_$part"
  done_parts+=("$part")
  { grep -vxF -- "$part" "$INSTALLED" 2>/dev/null || true; echo "$part"; } >"$INSTALLED.new"
  mv "$INSTALLED.new" "$INSTALLED"
done
current_part=""
rm -rf "$STAGE"
record_source
if $restart_shell; then
  omarchy-restart-shell >/dev/null 2>&1 || echo "install.sh: restart the shell to load the update: omarchy-restart-shell" >&2
fi
exit 0
