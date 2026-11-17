#!/usr/bin/env bash
# Starts the test VM in a window, with SSH forwarded to localhost:2222.
#   run.sh install   boot Omarchy's installer image
#   run.sh           boot the installed system
# Also serves $FATHOM_VM/serve on localhost:8765, which the VM reaches as
# 10.0.2.2:8765 (for setup.sh, capture.sh and fwtest.sh).
set -euo pipefail
vm=${FATHOM_VM:-$HOME/VMs/omarchy-test}
cd "$vm"
iso=$(ls omarchy-*.iso 2>/dev/null | tail -1)
extra=()
[[ ${1:-} == install ]] && extra=(-cdrom "$iso" -boot order=d)
python3 -m http.server 8765 --bind 127.0.0.1 --directory serve >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null' EXIT
qemu-system-x86_64 \
  -name "Omarchy test (Fathom)" -enable-kvm -machine q35 -cpu host -smp 4 -m 8G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=vars.fd \
  -drive file=disk.qcow2,if=virtio,format=qcow2 \
  -device virtio-vga-gl -display gtk,gl=on,zoom-to-fit=on \
  -device qemu-xhci -device usb-tablet -device usb-kbd \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
  -audiodev none,id=snd \
  "${extra[@]}"
