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

## Results

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
