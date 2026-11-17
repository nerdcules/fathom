#!/usr/bin/env bash
# Runs a command in the test VM's desktop session over SSH:
#   vm.sh [-t] '<command>'       (-t: give it a terminal, for sudo)
# The session's environment comes from the VM's running Hyprland, as a
# terminal there would have it; Hyprland doesn't carry its own instance
# signature or Wayland socket, so those are read from /run/user.
# $FATHOM_VM_USER is the user made in the VM's installer.
vm=${FATHOM_VM:-$HOME/VMs/omarchy-test}
user=${FATHOM_VM_USER:?set FATHOM_VM_USER to the VM user name}
tty=()
[[ ${1:-} == -t ]] && { tty=(-tt); shift; }
exec ssh "${tty[@]}" -p 2222 -i "$vm/vm_key" -o IdentitiesOnly=yes -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$vm/known_hosts" "$user@127.0.0.1" \
  'while IFS= read -r -d "" kv; do case ${kv%%=*} in OMARCHY_PATH|PATH|XDG_*|DBUS_SESSION_BUS_ADDRESS|DISPLAY|QT_*|GDK_*) export "$kv";; esac; done < /proc/$(pgrep -u "$USER" -x Hyprland | head -1)/environ; export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/$(id -u)/hypr | head -1) WAYLAND_DISPLAY=$(ls /run/user/$(id -u) | grep -m1 -E "^wayland-[0-9]+$"); '"$1"
