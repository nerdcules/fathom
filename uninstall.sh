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

# The bar's look from before Fathom made it glassy, if it's still glassy.
if [[ -s $STATE_DIR/previous-bar && $(omarchy bar background 2>/dev/null || true) == glassy ]]; then
  bar=$(<"$STATE_DIR/previous-bar")
  if [[ $bar == opaque || $bar == none ]]; then
    omarchy bar background "$bar" >/dev/null && echo "Put the bar back to $bar."
  fi
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

# fathom-update and its settings (what it recorded goes with ~/.local/state/fathom).
rm -f "$HOME/.local/bin/fathom-update" "${XDG_CONFIG_HOME:-$HOME/.config}/fathom/update.json"

# What fathom-look builds the theme from, the command, and your look.
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/fathom/theme"
rm -f "$HOME/.local/bin/fathom-look" "${XDG_CONFIG_HOME:-$HOME/.config}/fathom/look.json"

HYPR="$HOME/.config/hypr"
PLUGINS="$HOME/.config/omarchy/plugins"
hypr_changed=false

# First take Fathom's block out of hyprland.lua and reload, while every file
# it requires is still there. Hyprland reloads by itself when a file changes,
# and a reload that finds a required file gone can freeze it: in the test VM
# (tests/vm) uninstall froze Hyprland twice in seven runs when the files went
# first; with a dummy module, deleting the file first froze it once in three
# rounds, removing the require first never in twelve.
main="$HYPR/hyprland.lua"
if [[ -f $main ]] && grep -q "^-- fathom: begin" "$main"; then
  sed -i "/^-- fathom: begin/,/^-- fathom: end\$/d" "$main"
  hyprctl reload >/dev/null 2>&1 || true
fi

# Mini-player: stop it, then remove the bar widget, keys, rules and command.
if [[ -e $HOME/.local/bin/fathom-player || -d $PLUGINS/fathom.player ]]; then
  "$HOME/.local/bin/fathom-player" stop >/dev/null 2>&1 || true
  omarchy plugin disable fathom.player >/dev/null 2>&1 || true
  rm -rf "$PLUGINS/fathom.player"
  rm -f "$HYPR/fathom-player.lua" "$HOME/.local/bin/fathom-player"
  hypr_changed=true
  echo "Removed the mini-player."
fi

# Desk: close it, then remove the plugin, keys and command. Hyprland's
# reload at the end puts Omarchy's own Alt+Tab and Super+Tab back.
if [[ -e $HOME/.local/bin/fathom-desk || -d $PLUGINS/fathom.desk ]]; then
  omarchy-shell shell hide fathom.desk >/dev/null 2>&1 || true
  hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || true
  omarchy plugin disable fathom.desk >/dev/null 2>&1 || true
  rm -rf "$PLUGINS/fathom.desk"
  rm -f "$HYPR/fathom-desk.lua" "$HOME/.local/bin/fathom-desk"
  hypr_changed=true
  echo "Removed the desk."
fi

# Command Deck and Care: close the deck, stop Care's timer, then remove the
# plugin, keys, commands and units.
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if [[ -e $HOME/.local/bin/fathom-deck || -d $PLUGINS/fathom.deck || -f $UNITS/fathom-care.timer ]]; then
  omarchy-shell shell hide fathom.deck >/dev/null 2>&1 || true
  systemctl --user disable --now fathom-care.timer >/dev/null 2>&1 || true
  rm -f "$UNITS/fathom-care.timer" "$UNITS/fathom-care.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  omarchy plugin disable fathom.deck >/dev/null 2>&1 || true
  rm -rf "$PLUGINS/fathom.deck"
  rm -f "$HYPR/fathom-deck.lua" "$HOME/.local/bin/fathom-deck" "$HOME/.local/bin/fathom-care" "$HOME/.local/bin/fathom-start"
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/fathom/start.json"
  rmdir "${XDG_CONFIG_HOME:-$HOME/.config}/fathom" 2>/dev/null || true
  hypr_changed=true
  echo "Removed the Command Deck."
fi

# Mail: stop watching, forget every sign-in (the keyring entries), and
# remove the command, its service and your account settings.
if [[ -e $HOME/.local/bin/fathom-mail || -f $UNITS/fathom-mail.service ]]; then
  systemctl --user disable --now fathom-mail.service >/dev/null 2>&1 || true
  rm -f "$UNITS/fathom-mail.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  secret-tool clear application fathom-mail >/dev/null 2>&1 || true
  rm -f "$HOME/.local/bin/fathom-mail" "${XDG_CONFIG_HOME:-$HOME/.config}/fathom/mail.json"
  rmdir "${XDG_CONFIG_HOME:-$HOME/.config}/fathom" 2>/dev/null || true
  rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/fathom/mail"
  rmdir "${XDG_DATA_HOME:-$HOME/.local/share}/fathom" 2>/dev/null || true
  echo "Removed Fathom Mail and its sign-ins."
fi

# Sentinel: stop watching, remove the watcher, its key and state, then its
# root parts (asks for your password), including OpenSnitch if Fathom
# installed it.
if [[ -e $HOME/.local/bin/fathom-sentinel || -f $UNITS/fathom-sentinel.service || -d /usr/local/lib/fathom-sentinel ]]; then
  systemctl --user disable --now fathom-sentinel.service >/dev/null 2>&1 || true
  rm -f "$UNITS/fathom-sentinel.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  rm -f "$HOME/.local/bin/fathom-sentinel" "$HYPR/fathom-sentinel.lua" "${XDG_CONFIG_HOME:-$HOME/.config}/fathom/sentinel.json"
  rmdir "${XDG_CONFIG_HOME:-$HOME/.config}/fathom" 2>/dev/null || true
  rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/fathom/sentinel"
  rmdir "${XDG_DATA_HOME:-$HOME/.local/share}/fathom" 2>/dev/null || true
  if [[ -d /usr/local/lib/fathom-sentinel ]]; then
    if [[ -t 0 ]]; then
      sudo bash "$REPO/sentinel/install-root.sh" uninstall
    else
      pkexec bash "$REPO/sentinel/install-root.sh" uninstall
    fi
  fi
  hypr_changed=true
  echo "Removed Sentinel."
fi

# Pulse: stop collecting, remove the command, its key and service, and the
# firewall rule that let containers reach it (asks for your password).
if [[ -e $HOME/.local/bin/fathom-pulse || -f $UNITS/fathom-pulse.service ]]; then
  systemctl --user disable --now fathom-pulse.service >/dev/null 2>&1 || true
  rm -f "$UNITS/fathom-pulse.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  rm -f "$HOME/.local/bin/fathom-pulse" "$HYPR/fathom-pulse.lua"
  rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/fathom/pulse"
  rmdir "${XDG_DATA_HOME:-$HOME/.local/share}/fathom" 2>/dev/null || true
  if [[ -s $STATE_DIR/pulse-bridge ]] && command -v ufw >/dev/null; then
    bridge=$(<"$STATE_DIR/pulse-bridge")
    # With its comment, ufw deletes only Fathom's rule: without one it also
    # deletes any rule of yours that matches apart from the comment.
    rule=(delete allow proto tcp from 172.16.0.0/12 to "$bridge" port 4317,4318 comment fathom-pulse)
    if [[ -t 0 ]]; then
      sudo ufw "${rule[@]}" >/dev/null || true
    else
      pkexec ufw "${rule[@]}" >/dev/null || true
    fi
  fi
  hypr_changed=true
  echo "Removed Pulse."
fi

# Crumbs: its command and key, then its helper and the cookie rules it
# wrote (asks for your password).
if [[ -e $HOME/.local/bin/fathom-crumbs || -d /usr/local/lib/fathom-crumbs ]]; then
  rm -f "$HOME/.local/bin/fathom-crumbs" "$HYPR/fathom-crumbs.lua"
  if [[ -d /usr/local/lib/fathom-crumbs ]]; then
    if [[ -t 0 ]]; then
      sudo bash "$REPO/crumbs/install-root.sh" uninstall
    else
      pkexec bash "$REPO/crumbs/install-root.sh" uninstall
    fi
  fi
  hypr_changed=true
  echo "Removed Crumbs and its cookie rules."
fi

# The phone service: stop it, remove it and its firewall rules (each by its
# comment, so a rule of yours that matches is kept), its key and the phones
# paired with it.
if [[ -e $HOME/.local/bin/fathom-phone || -f $UNITS/fathom-phone.service ]]; then
  systemctl --user disable --now fathom-phone.service >/dev/null 2>&1 || true
  rm -f "$UNITS/fathom-phone.service" "$HOME/.local/bin/fathom-phone" "${XDG_CONFIG_HOME:-$HOME/.config}/fathom/phone.json"
  systemctl --user daemon-reload
  hex=$(printf fathom-phone | od -An -tx1 | tr -d ' \n')
  if command -v ufw >/dev/null && grep -qs "comment=$hex" "${FATHOM_UFW_DIR:-/etc/ufw}/user.rules"; then
    cmds="ufw delete allow proto tcp from 192.168.0.0/16 to any port 4920 comment fathom-phone >/dev/null 2>&1;"
    cmds+=" ufw delete allow proto tcp from 10.0.0.0/8 to any port 4920 comment fathom-phone >/dev/null 2>&1;"
    cmds+=" ufw delete allow proto tcp from 172.16.0.0/12 to any port 4920 comment fathom-phone >/dev/null 2>&1;"
    cmds+=" ufw delete allow in on tailscale0 to any port 4920 proto tcp comment fathom-phone >/dev/null 2>&1; true"
    if [[ -t 0 ]]; then
      sudo bash -c "$cmds"
    else
      pkexec bash -c "$cmds"
    fi
  fi
  echo "Removed the phone service and its pairings."
fi

# Instant alerts: ntfy's service and settings, Fathom's own copy of ntfy
# (a package's stays), the pings it held and its firewall rules.
if [[ -f $UNITS/fathom-push.service ]]; then
  systemctl --user disable --now fathom-push.service >/dev/null 2>&1 || true
  rm -f "$UNITS/fathom-push.service"
  systemctl --user daemon-reload
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/fathom/ntfy" "${XDG_STATE_HOME:-$HOME/.local/state}/fathom/ntfy" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/fathom/ntfy"
  hex=$(printf fathom-push | od -An -tx1 | tr -d ' \n')
  if command -v ufw >/dev/null && grep -qs "comment=$hex" "${FATHOM_UFW_DIR:-/etc/ufw}/user.rules"; then
    cmds=""
    for src in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
      cmds+="ufw delete allow proto tcp from $src to any port 4921 comment fathom-push >/dev/null 2>&1; "
    done
    cmds+="ufw delete allow in on tailscale0 to any port 4921 proto tcp comment fathom-push >/dev/null 2>&1; true"
    if [[ -t 0 ]]; then
      sudo bash -c "$cmds"
    else
      pkexec bash -c "$cmds"
    fi
  fi
  echo "Removed instant alerts (ntfy)."
fi

# The shell forgets the plugins removed above. (Their Hyprland block went
# first, at the top.)
if $hypr_changed; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

if [[ -d /usr/share/sddm/themes/fathom || -f /etc/sddm.conf.d/99-zz-fathom.conf ]]; then
  if [[ -t 0 ]]; then
    sudo bash "$REPO/signin/install-root.sh" uninstall
  else
    pkexec bash "$REPO/signin/install-root.sh" uninstall
  fi
fi

# Last, so nothing that was just stopped writes it again.
rm -rf "$STATE_DIR"
