#!/usr/bin/env bash
# Starts the test VM, with SSH forwarded to localhost:2222.
#   run.sh install   boot Omarchy's installer image
#   run.sh           boot the installed system
# Also serves $FATHOM_VM/serve on localhost:8765, which the VM reaches as
# 10.0.2.2:8765 (for setup.sh, capture.sh and fwtest.sh), and opens QEMU's
# control socket as $FATHOM_VM/qmp.sock (qmp.py uses it).
#
# FATHOM_VM_DISPLAY=gtk (the default): a window, with 3D (virtio-vga-gl).
# FATHOM_VM_DISPLAY=vnc: no window and no 3D (virtio-vga), the screen on VNC
#   at 127.0.0.1:5900, for a machine with no GPU Linux can render with, such
#   as WSL2 (README.md here: "On Windows 11").
# With vnc, if $FATHOM_VM/passphrase exists (yours alone: chmod 600),
# qmp.py types it at the disk's passphrase prompt, once, in the layout named
# in $FATHOM_VM/keymap (uk or us; us if there's none). It logs to
# $FATHOM_VM/logs/unlock.log. With gtk, type it in the window.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vm=${FATHOM_VM:-$HOME/VMs/omarchy-test}
cd "$vm"
extra=()
if [[ ${1:-} == install ]]; then
  # Only the installer needs the image; a copied VM may not have it.
  iso=$(ls omarchy-*.iso 2>/dev/null | tail -1 || true)
  [[ -n $iso ]] || { echo "run.sh: no omarchy-*.iso in $vm (make-vm.sh downloads it)" >&2; exit 1; }
  extra=(-cdrom "$iso" -boot order=d)
fi
case ${FATHOM_VM_DISPLAY:-gtk} in
  gtk) display=(-device virtio-vga-gl -display gtk,gl=on,zoom-to-fit=on) ;;
  vnc) display=(-device virtio-vga -display vnc=127.0.0.1:0) ;;
  *) echo "run.sh: FATHOM_VM_DISPLAY is gtk or vnc" >&2; exit 1 ;;
esac
python3 -m http.server 8765 --bind 127.0.0.1 --directory serve >/dev/null 2>&1 &
server=$!
helper=
trap 'kill $server $helper 2>/dev/null' EXIT
rm -f qmp.sock
if [[ -f passphrase && ${1:-} != install ]]; then
  if [[ ${FATHOM_VM_DISPLAY:-gtk} != vnc ]]; then
    # With 3D, QEMU can't read the screen once the VM's driver takes it
    # ("no surface"), so qmp.py would never see the prompt.
    echo "run.sh: the passphrase is typed only with FATHOM_VM_DISPLAY=vnc; type it in the window" >&2
  elif [[ $(stat -c %a passphrase) != 600 ]]; then
    echo "run.sh: $vm/passphrase must be yours alone (chmod 600 it); not typing it" >&2
  else
    mkdir -p logs
    python3 -I "$here/qmp.py" "$vm/qmp.sock" unlock "$(cat keymap 2>/dev/null || echo us)" \
      <passphrase >>logs/unlock.log 2>&1 &
    helper=$!
  fi
fi
qemu-system-x86_64 \
  -name "Omarchy test (Fathom)" -enable-kvm -machine q35 -cpu host -smp 4 -m 8G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=vars.fd \
  -drive file=disk.qcow2,if=virtio,format=qcow2 \
  "${display[@]}" \
  -device qemu-xhci -device usb-tablet -device usb-kbd \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
  -audiodev none,id=snd \
  -qmp "unix:$vm/qmp.sock,server,nowait" \
  "${extra[@]}"
