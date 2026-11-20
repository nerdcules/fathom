# Checks in a real Omarchy VM

`tests/` checks install.sh, uninstall.sh and Sentinel's firewall helper
with stand-in commands. These scripts check them for real, in a disposable
Omarchy virtual machine: an upgrade from an older Fathom, uninstall, a fresh
install, the opt-in parts (Sentinel, Pulse, Crumbs, the sign-in screen), the
firewall buttons against the real ufw, and a full uninstall beside a ufw rule
of the user's. Nothing here touches the machine running the VM.

## Once: make the VM

Needs `qemu-desktop` and `edk2-ovmf` (`omarchy pkg add qemu-desktop edk2-ovmf`),
KVM, about 8 GB of memory free while it runs, and 60 GB of disk (the image
fills as it's used; 19 GB after installing Omarchy).

```bash
tests/vm/make-vm.sh          # in ~/VMs/omarchy-test, or set FATHOM_VM
tests/vm/run.sh install      # a window with Omarchy's installer
```

`make-vm.sh` downloads Omarchy's installer image (4.0.6, 6,448,529,408
bytes; 4.5.0 shipped without one) and checks its SHA256 against Omarchy's
release notes. In the window, install Omarchy onto the 60 GB virtual disk
with any user name, then update it (`omarchy update`) so it matches the
Omarchy you test against. Then, in a terminal in the VM:

```bash
curl -s http://10.0.2.2:8765/setup.sh | bash
```

That gives the VM's user passwordless sudo (so root steps can run
unattended: only for a throwaway VM), starts sshd, lets SSH through
Omarchy's firewall, and adds the key `make-vm.sh` made. Later, start the VM
with `tests/vm/run.sh`; it serves `setup.sh`, `capture.sh` and `fwtest.sh`
to the VM at `10.0.2.2:8765` while it runs.

Keyboard keys like Super go to the machine running the VM until you press
Ctrl+Alt+G in the VM window (again to let go).

Omarchy's installer encrypts the disk, so each boot stops at "A password is
required to access the root volume". Type it in the window, or, with
`FATHOM_VM_DISPLAY=vnc` (below), let `run.sh` type it. With the window (the
default) it can't: once the VM's 3D driver takes the screen, QEMU can't
read it ("no surface", from 7 s into the boot on this laptop), so the prompt
is never seen. For `vnc`, put it in `$FATHOM_VM/passphrase` (readable by you alone,
`chmod 600`; `run.sh` won't use it otherwise) and the VM's keyboard layout
at that prompt, `uk` or `us`, in `$FATHOM_VM/keymap` (`us` if there's
none). `qmp.py` then watches the screen through QEMU's control socket
(`$FATHOM_VM/qmp.sock`), types it once when the prompt shows, and logs to
`$FATHOM_VM/logs/unlock.log`. It never types a second time, so a wrong
passphrase in the file leaves the prompt waiting for you rather than using
up systemd's tries. It types only letters, digits, `#` and `~`. Anyone who
can read that file and the disk image can open the VM's disk: fine for a
throwaway VM, not for one holding anything of yours.

`FATHOM_VM_DISPLAY=vnc tests/vm/run.sh` starts the VM with no window and no
3D (`virtio-vga`, the screen on VNC at `127.0.0.1:5900`), for a machine with
no GPU that Linux can render with; the default, `gtk`, is the window with 3D
(`virtio-vga-gl`). Hyprland in the VM then draws without the host's GPU.

## Each time: run the checks

With the VM running and Fathom not installed in it:

```bash
FATHOM_VM_USER=<the VM's user> tests/vm/check.sh [older-ref]
```

It copies this checkout into the VM, uncommitted changes included, and an
older Fathom (default `e132146`, before issues #1–#3), then runs every step
in the VM's desktop session over SSH (`vm.sh`), printing PASS or FAIL for
each. Uninstalls are compared with a capture taken before the first install
(`capture.sh`): theme, bar, `shell.json`, ufw rules, Fathom's folders,
`hyprland.lua`, units and system files. Two differences are allowed: the
`hyprland.lua.bak.<time>` backups install.sh makes (uninstall leaves them,
as the main README says), and Omarchy rewriting the bar setting in
`shell.json` (`"transparent": false` becomes `"background": "opaque"`).
`fwtest.sh` is the real-ufw check for issue #1. Last, `fathom-update`: it
installs the desk from a git clone tagged v0.1.0, publishes a v0.2.0 that
changes the desk in a repository inside the VM, and checks `fathom-update
check`, `apply` and `rollback` against the plugin actually installed. Logs go to
`~/VMs/omarchy-test/logs/<time>-<commit>`.

Each step has 5 minutes; a step that hangs fails rather than stopping the
check. Fathom's lockdown blocks new SSH connections into the VM, so the
checks always end it before connecting again.

## On Windows 11 (WSL2)

The same scripts run in an Arch Linux distro under WSL2, with QEMU using KVM
through WSL's nested virtualization. Checked once, on 18 November 2026 (see
Results): Windows 11 Pro build 26300, WSL 2.7.13 (kernel 6.18.33.2), an
i7-8700 with 64 GB.

What differs from a Linux machine, and what to do about it:

- **No 3D.** WSL has no `/dev/dri`, only `/dev/dxg`, so QEMU's
  `egl-headless` fails ("no drm render node available"), and its GTK
  window, with or without GL, never got as far as opening the control socket
  when started from an SSH session into Windows (12 s each; from a desktop
  session on the PC it wasn't tried). Use `FATHOM_VM_DISPLAY=vnc`: Omarchy's
  Hyprland came up with it, and every check passed.
- **Windows programs from WSL.** With systemd on, Arch's `systemd-binfmt`
  clears WSL's interop entry, and Windows programs fail with "Exec format
  error". Microsoft's fix: `echo ':WSLInterop:M::MZ::/init:PF' | sudo tee
  /etc/binfmt.d/WSLInterop.conf`, then restart the distro.
- **Slow downloads in WSL** (on that PC; it may not happen on yours). A
  130,369-byte file came at 942,967 B/s from Windows and 76,933 B/s from WSL,
  and pacman's first download crawled at about 0.17 MB/s. Having pacman
  download with Windows' `curl.exe` instead (an `XferCommand` script that
  runs `/mnt/c/Windows/System32/curl.exe -s -S -L -f -C - -o "$(wslpath -w
  "$2")" "$1"`, with `DownloadUser` commented out, since curl.exe's files
  don't arrive as pacman's download user) took the same install from more
  than 25 minutes, unfinished, to 87 s. pacman still checks each package's
  signature.

Setting it up, in PowerShell on the PC:

```powershell
wsl --install archlinux --name fathom-test --no-launch
wsl -d fathom-test -u root -- pacman-key --init
wsl -d fathom-test -u root -- pacman-key --populate archlinux
# the interop fix above, and the curl.exe downloads if WSL's are slow, then:
wsl -d fathom-test -u root -- pacman -Syu --noconfirm qemu-desktop edk2-ovmf openssh git python jq sudo
```

Then make a user in the `kvm` group, and give the distro the VM: either
`make-vm.sh` and an install (`run.sh install` needs a window, so not with
`vnc`), or a copy of a VM already made on another machine: its
`disk.qcow2`, `vars.fd` and `vm_key`, into `~/VMs/omarchy-test` on WSL's own
disk, not under `/mnt/c`. Fathom must not be installed in the copy. Clone
this repo there too, with its history: `check.sh` installs the older commit
from it.

```bash
FATHOM_VM_DISPLAY=vnc tests/vm/run.sh &    # with passphrase and keymap set (above)
FATHOM_VM_USER=<the VM's user> tests/vm/check.sh
```

## Results

### 20 November 2026, Windows 11 (WSL2)

Same PC and VM as on 18 November (Omarchy 4.5.0-3), `FATHOM_VM_DISPLAY=vnc`,
driven over SSH from the laptop. At 3badc94 with the changes for issues
#5-#8 uncommitted (committed unchanged as 82bbfb4 to 8a5c41f): `check.sh`
26 passed, 0 failed, in 84 s; nothing of Fathom's was left in the VM after
it.

- Before it, `check.sh` stopped at "Fathom is not installed in the VM to
  start with": the desk part and `fathom-update` from the last 18 November
  run were still there (state `installed` = desk, from the v0.1.0 clone),
  although that run's `update-uninstall.log` says "Removed the desk." with
  exit 0. Cleaned with `~/fathom-new/uninstall.sh`. Cause not found; this run
  didn't repeat it.
- WSL stops the distro, and QEMU with it, when no `wsl.exe` session is open
  for a while: SSH into the VM was refused minutes after the boot's own
  session ended. Keeping one `wsl.exe -d fathom-test -- sleep` open over SSH
  for the whole session kept it up.
- Real keys and clicks through QEMU's QMP (`input-send-event`), not in
  `check.sh`: Super+Tab held with Tab x3 then let go went to workspace 3;
  a tap then Tab and Enter went to workspace 2; Esc while held changed
  nothing; the Start power menu opened above its button and asked in
  place; the screensaver preview opened and closed on a key.

### 18 November 2026, Windows 11 (WSL2)

PC: Windows 11 Pro build 26300, WSL 2.7.13 (kernel 6.18.33.2), an Arch
Linux distro with QEMU 11.1.3 and KVM, an i7-8700 with 64 GB. VM: the same
one as below (Omarchy 4.5.0-3), its `disk.qcow2` and `vars.fd` copied from
this laptop (SHA256 the same after the copy), with `FATHOM_VM_DISPLAY=vnc`
(no 3D). Driven over SSH from this laptop.

- At 0100fa8, with the old `run.sh` changed by hand to VNC and the
  passphrase typed through QMP: `check.sh` 26 passed, 0 failed, in 86 s.
- At 0100fa8 with this work uncommitted, two boots by the new `run.sh`, each
  with a full `check.sh`: 26 passed, 0 failed, in 84 s (before the last two
  changes: "no surface" in `qmp.py`, and typing only with `vnc`), then 26
  passed, 0 failed, in 80 s with the scripts committed as 2113525.
  `fwtest.sh` inside it: 15 passed, 0 failed in all three runs.
- The unlock, with 2113525's `run.sh` and `qmp.py` (the same SHA256 on the PC
  as here): the prompt was seen at 11 s, typed once, not asked again; the VM
  answered SSH about 16 s after `run.sh` started.
- On this laptop, `run.sh` with the default GTK window started and quit
  cleanly (exit 0) with the control socket added; the unlock can't work
  there (above). Then, at 3d02c4b (2113525's scripts, clean tree), with the
  default GTK window and the disk unlocked at the window's prompt: `check.sh`
  26 passed, 0 failed, in 78 s; `fwtest.sh` inside it 15 passed, 0 failed.
- The phone part (`--phone`) isn't in these checks.

### 18 November 2026 (0.2.0)

Same VM: Omarchy 4.5.0-3, ufw 0.36.2. Checked 4591e64 against e132146:
`check.sh` 26 passed, 0 failed, in 80 s or so; `fwtest.sh` 15 passed, 0
failed. The first run, at 814f460, had one failure: the "they are this
checkout's" comparison, since install.sh now writes the version into the
installed `Version.js` (de83adc). The check leaves that file out now, and
a new one makes sure the deck's and desk's copies were written (4591e64).
The phone part (`--phone`) isn't in these checks.

### 17 November 2026

VM: Omarchy 4.0.6 image updated to 4.5.0-3, ufw 0.36.2 with IPv6 on,
4 CPUs and 8 GB under QEMU 11.1.2 with KVM. Checked: 846553a with the
changes since committed as 6b4f7d0 (the uninstall order) and 0877ec1 (the
sign-in message), against e132146.

- Three runs in a row of `check.sh`: 17 passed, 0 failed each; 52 to 55 s
  each. `fwtest.sh`: 15 passed, 0 failed in each.
- Found and fixed with these runs:
  - **uninstall.sh could freeze Hyprland.** It deleted each part's
    `fathom-*.lua` and only then took the `require` lines out of
    `hyprland.lua`; Hyprland reloads by itself when files change, and a
    reload that finds a required file gone sometimes deadlocks it (stuck in
    `futex_wait`, `hyprctl` unanswered, the screen frozen; only a reboot
    cleared it). It froze twice in 7 uninstalls. With a dummy module and no
    Fathom code: deleting the file first froze it once in 3 rounds; removing
    the `require` first, 0 in 12. uninstall.sh now removes the block and
    reloads before any file goes: 9 uninstalls since, none froze.
  - While Hyprland was frozen, the uninstall's `omarchy plugin disable`
    calls (which ignore failure) left `fathom.deck` and `fathom.desk` in
    `shell.json` although their folders were gone. `check.sh` now refuses
    to start while `shell.json` names a Fathom plugin.
  - The sign-in step said "This laptop signs in automatically at boot" on
    every machine; it now reads SDDM's `[Autologin]` and says so only when
    it applies. The first version of that check stopped `--signin` where
    `/etc/sddm.conf` doesn't exist (the VM); caught here, fixed.
- With `fathom-update` (332a7c4 and the fix to this step's setup): one run,
  25 passed, 0 failed in 75 s; the update step found v0.2.0 (one part,
  desk, no password), `apply` installed it, `rollback` put v0.1.0's back.
- Earlier the same day, by hand with the same steps: the same results,
  including `fwtest.sh`'s 15 checks (one first failed through the test's
  own error: it expected one interface rule where ufw makes two with IPv6
  on).
