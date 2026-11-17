#!/bin/bash
# capture.sh <name>: what Fathom may touch, saved under ~/captures/<name>
d=~/captures/$1; rm -rf "$d"; mkdir -p "$d"
omarchy theme current > "$d/theme" 2>&1
omarchy bar background > "$d/bar" 2>&1
jq -S . ~/.config/omarchy/shell.json > "$d/shell.json" 2>&1
sudo cat /etc/ufw/user.rules /etc/ufw/user6.rules 2>/dev/null | grep '^### tuple' > "$d/ufw-tuples"
ls -1 ~/.config/omarchy/themes ~/.config/omarchy/plugins ~/.local/bin ~/.config/hypr 2>&1 > "$d/files"
find ~/.config/fathom ~/.local/share/fathom ~/.local/state/fathom -maxdepth 2 2>/dev/null | sort > "$d/fathom-dirs"
md5sum ~/.config/hypr/hyprland.lua > "$d/hyprland.md5"
grep -n "fathom" ~/.config/hypr/hyprland.lua > "$d/hyprland-fathom" 2>&1
systemctl --user list-unit-files 'fathom*' --no-legend > "$d/user-units" 2>&1
systemctl list-unit-files 'fathom*' --no-legend > "$d/system-units" 2>&1
ls -1 /usr/local/lib /etc/sddm.conf.d /etc/opt/edge/policies/managed /etc/chromium/policies/managed 2>&1 > "$d/system-files"
echo "captured $1"
