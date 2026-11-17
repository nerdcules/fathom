#!/usr/bin/env bash
# Makes a disposable Omarchy VM for Fathom's checks (see README.md here).
#   make-vm.sh                 in $FATHOM_VM (default ~/VMs/omarchy-test)
# Downloads Omarchy's installer image and checks it against the SHA256 in
# Omarchy's release notes, makes a 60 GB disk (it fills as used), the UEFI
# settings file, an SSH key for this VM only, and serve/setup.sh carrying
# that key. Needs qemu-desktop and edk2-ovmf, curl and ssh-keygen.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vm=${FATHOM_VM:-$HOME/VMs/omarchy-test}
# The newest Omarchy image when this was written (4.5.0 shipped without one);
# update both together, from the release notes at github.com/basecamp/omarchy.
ISO=omarchy-4.0.6.iso
SHA=b542db5fecc37395d9af6654a8146ebed225f275ae4d5a6fcf432e40afe7bb88

for tool in qemu-system-x86_64 qemu-img curl ssh-keygen; do
  command -v "$tool" >/dev/null || { echo "make-vm.sh: needs $tool (qemu-desktop, curl, openssh)" >&2; exit 1; }
done
[[ -f /usr/share/edk2/x64/OVMF_VARS.4m.fd ]] || { echo "make-vm.sh: needs edk2-ovmf" >&2; exit 1; }

mkdir -p "$vm/serve" "$vm/logs"
cd "$vm"
if [[ ! -f $ISO ]]; then
  curl -fL --progress-bar -o "$ISO.part" "https://iso.omarchy.org/$ISO"
  mv "$ISO.part" "$ISO"
fi
echo "$SHA  $ISO" | sha256sum -c -
[[ -f disk.qcow2 ]] || qemu-img create -q -f qcow2 disk.qcow2 60G
[[ -f vars.fd ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd vars.fd
[[ -f vm_key ]] || ssh-keygen -q -t ed25519 -N "" -C fathom-vm-test -f vm_key
sed "s|@KEY@|$(cat vm_key.pub)|" "$here/setup.sh.in" > serve/setup.sh
cp "$here/capture.sh" "$here/fwtest.sh" serve/
echo "Made $vm. Next: $here/run.sh install, then follow README.md."
