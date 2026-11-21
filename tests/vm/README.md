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

### Issue #14, Agents: 21 November 2026, Windows 11 (WSL2)

Same PC and VM, from the working tree before it was committed (labelled
`137102b-dirty`).

- `check.sh` 27 passed, 0 failed.
- `./install.sh --desk` put `fathom.agents` in `omarchy.agents`'s place.
  The VM has 23 usage records but no agent with anything to show, so the
  dropdown opened on Omarchy's sign-in words, "Start the default agent",
  "Add an account" and the three starters; Down twice (real keys, QMP) put
  the focus ring on "Add an account". The shell's log had no error from
  it, only "Handler was registered but will not be used" while it took
  the item's place, as the others do.
- `uninstall.sh` put `omarchy.agents` back.
- Not tried in the VM: limits, accounts, a balance, signing in.

### Issue #14, Tailscale: 21 November 2026, Windows 11 (WSL2)

Same PC and VM, from the working tree before it was committed (labelled
`137102b-dirty`).

- `check.sh` 27 passed, 0 failed.
- The VM has no Tailscale. With `omarchy.tailscale` put on the bar,
  `./install.sh --desk` put `fathom.tailscale` in its place;
  `omarchy-shell omarchy.tailscale status` said "Not installed", and the
  dropdown showed Omarchy's "Tailscale CLI is not installed or not on
  PATH." and nothing else. The shell's log had no error from it.
- `uninstall.sh` put `omarchy.tailscale` back.
- Tried on the laptop instead (Tailscale running, one machine online):
  the dropdown with live data, and, by the user, the keys and buttons.
  Not tried anywhere: several accounts, exit nodes, Mullvad, Taildrop.

### Issues #15-#21, the design review: 21 November 2026, Windows 11 (WSL2)

Same PC and VM, from the working tree at `d8bc6fc` (labelled
`137102b-dirty`).

- `check.sh` 27 passed, 0 failed.
- `./install.sh --deck --desk`, then real keys through QMP in Quick
  settings: Super+Alt+A opened it; Down put the focus ring on Wi-Fi;
  Right opened Wi-Fi's list ("No Wi-Fi on this machine", as the VM has
  none); Left came back to the tiles with the ring on Wi-Fi; Esc closed it.
  The idle pills (Lock, Menu, copy) showed their edge and the key line
  showed at the foot.
- The shell's log after the install: no error from Fathom's QML; two
  "Handler was registered but will not be used" lines while the clock and
  weather dropdowns took their items' places, as before.
- Not checked here: Personalise at other corner settings (#19) and the
  status marks (#17), which the VM's deck has none of to show; both seen
  on the laptop.

### Issue #22, one kit: 21 November 2026, Windows 11 (WSL2)

Same PC and VM, from the working tree before it was committed (labelled
`137102b-dirty`; the tree went over as a tar, with the plugins' `kit/`
links).

- `check.sh` 27 passed, 0 failed. Its update check now changes
  `QuickTile.qml` instead of the desk's `Glass.qml`, which moved to the kit.
- `./install.sh --deck --desk`: each installed plugin got `kit/` as a real
  folder. Quick settings, the calendar dropdown, the deck and Start opened
  and drew as before (screenshots, not kept).
- The shell's log after the install: no error from Fathom's QML except
  one `TypeError` from the skin's `t()` at the shell's start; the VM's
  journal has 16 earlier ones from the desk's own `Skin.qml`, the first on
  18 November, so the kit didn't bring it.

### Issue #14, the weather: 21 November 2026, Windows 11 (WSL2)

Same PC and VM, from the working tree before it was committed (labelled
`137102b-dirty`).

- `check.sh` 27 passed, 0 failed.
- `./install.sh --desk`: `fathom.weather` took `omarchy.weather`'s place
  in the centre. With no place set, it showed the temperature,
  feels-like, wind, humidity and two coming days for the place Omarchy's
  lookup found for the PC's network.
- Real input through QMP: clicking the place opened the search; typing
  "leeds" listed five places; Down and Return chose Leeds, Alabama, and
  wrote it to Omarchy's `weather.json`; the units became °F, by Omarchy's
  rule for a US place. "Use where I am" removed `weather.json` and the
  dropdown went back to the place found. `omarchy-shell omarchy.weather
  edit` opened it on the search; a right-click sent Omarchy's weather
  notification.
- Found: open-meteo answered this network with 403 to every request (the
  laptop got 200 in 0.12 s), and after a place was saved the field said
  "Loading…" for good: Omarchy's logic waits for open-meteo, and after
  three failed retries nothing ends the wait. Omarchy's own panel's
  spinner was still turning 8 seconds after a save. Fathom's now ends the
  wait when the retries run out; after that change, a save closed the
  search and showed the place.
- `uninstall.sh` left `shell.json` the same as the baseline, and no plugin.
- Not tried: open-meteo answering (it never did here), `unit` and
  `refreshMinutes` settings, Super+Ctrl+Alt+W.

### Issue #14, the clock: 20 November 2026, Windows 11 (WSL2)

Same PC and VM, from the working tree before it was committed (labelled
`137102b-dirty`, as below).

- `check.sh` 27 passed, 0 failed.
- `./install.sh --desk`: `fathom.clock` took `omarchy.clock`'s place at the
  start of the centre, with its settings; its label read "Friday 22:35".
- Real input through QMP: a click opened the calendar (November 2026, ISO
  weeks 45 to 50, the 20th lit, "2026 88%"). Left showed October, with
  Today; T came back. W wrote `"weekStartDay": "monday"` into the clone's
  entry in `shell.json`, and again `"sunday"`; a right-click on the label
  wrote `"format": "dddd h:mm AP"` and the label changed. Super+Ctrl+Alt+D
  opened it. A double-click on the year bar opened the two fields; typing
  1980, Tab, 85, Return wrote `"birthYear": 1980, "lifeExpectancy": 85`
  and the life bar showed 54%. Two wheel-ups on the grid went back to
  September. `omarchy-shell omarchy.clock toggle` opened it.
- With the clock's settings put back by hand, `uninstall.sh` left
  `shell.json` the same as the baseline, and no plugin.
- Not tried: the middle-click time zone menu, a vertical bar.

### Issue #14, the bar's dropdowns: 20 November 2026, Windows 11 (WSL2)

Same PC and VM, from the working tree before it was committed (a copy of
it in a scratch checkout on the PC, so `check.sh` labels it
`137102b-dirty`).

- `check.sh` 27 passed, 0 failed.
- `./install.sh --desk` on the VM's bar: Fathom's Display took
  `omarchy.monitor`'s place (`[omarchy.tray, omarchy.keyboard-layout,
  omarchy.agents, fathom.display, fathom.desk]`), and the install named the
  ten bar items still without a Fathom dropdown. `uninstall.sh` put
  `omarchy.monitor` back: `shell.json` the same as the baseline, no plugin
  left. `omarchy plugin disable fathom.display` and `enable` swapped them
  back and forth in place.
- Real input through QMP: a click on the Display icon opened Fathom's
  dropdown (no brightness slider: the VM has no backlight). Down then
  Right set the text size from 12 to 14 px; Left set it back; Esc closed
  it. Clicking 1.25× set the scale to 1.25. Super+Ctrl+D opened it; Tab
  went on to Omarchy's Agents dropdown. `omarchy-shell shell toggle
  omarchy.monitor` opened it, and `omarchy-shell omarchy.monitor state`
  was answered by it.
- Found and fixed on the way: after a text size change the dropdown lost
  the keyboard (Esc did nothing), because each new description rebuilt
  every control; the factory now updates them in place, and the card is a
  focus scope. Omarchy's own Display panel kept the keyboard through the
  same change. The scale buttons said 3× where Omarchy's say 3.2× (what
  1280×800 really gets); they now say what the screen gets.
- Super+Ctrl+N opened Quick settings on its Wi-Fi list, but Omarchy's own
  bind ran too ("summon: no live bar widget for: omarchy.network"):
  `o.bind` adds a bind beside Omarchy's. With `o.rebind` there is one bind
  each for Super+Ctrl+A, B, D, N and P, and no warning.

### Issue #14: 20 November 2026, Windows 11 (WSL2)

Same PC and VM (Omarchy 4.5.0-3), `FATHOM_VM_DISPLAY=vnc`, driven over SSH
from the laptop. The VM's bar carries Omarchy's Bluetooth, network, audio
and power widgets, with Display between audio and power.

- At fb23edb (the cluster): `check.sh` 25 passed, 2 failed, both "back to
  the state before Fathom": the bar itself came back exactly, but
  `shell.json` kept `"plugins": [{"id": "fathom.desk"}]` (a desk installed
  before it had a bar widget has that record; `plugin disable` removed only
  the bar entry). Fixed in `uninstall.sh` (2e6cc26).
- At 2e6cc26: `check.sh` 27 passed, 0 failed, in 110 s.
- Real clicks through QMP at 2e6cc26, `./install.sh --desk` alone: the
  cluster went after Display, showing Ethernet and volume only (the VM has
  no Bluetooth and no battery). Click: Quick settings. Right-click: Quick
  settings on its Wi-Fi list ("No Wi-Fi on this machine."). Middle-click:
  `wpctl` said MUTED, then not after another. Scroll: no change (1.00);
  fixed in 137102b.
- At 137102b, reinstalled over it: the cluster stayed where it was; one
  scroll down 0.95, another 0.90, one up 0.95. `uninstall.sh` (exit 0):
  the four back in their places and `shell.json` the same as the baseline.

### 0.4.0: 20 November 2026, Windows 11 (WSL2)

Same PC and VM (Omarchy 4.5.0-3), `FATHOM_VM_DISPLAY=vnc`, driven over SSH
from the laptop.

- At 40e77d4 (the 0.4.0 changelog): `check.sh` 24 passed, 2 failed. The
  opt-in step stopped at Ward's question (new in 282060c: `--sentinel` asks
  at a terminal) and waited out its 5 minutes; the sign-in check after it
  failed with it. Fixed in the check, not in `install.sh` (798ad3b): it
  types "n" once the question shows. A first try typed it at the start;
  the VM echoed it at once and it was gone before the question came.
- At 798ad3b: `check.sh` 27 passed, 0 failed, in 71 s, the real-ufw checks
  among them 15 passed, 0 failed, and the new "asked about Ward once; no
  is remembered".
- The hover fix (dfb166e), with real pointer moves through QMP, at
  798ad3b, `./install.sh --deck` and six projects in `~/Work`: with the
  pointer on Restart in the power menu, only Restart lit up; on "Restart
  now?", only its button. The Recent row under it (bravo) stayed dark in
  both (it lit up at eb8d811, in the #13 entry below). No window opened.
  Then `uninstall.sh` (exit 0) and the projects removed.

### Issue #13: 20 November 2026, Windows 11 (WSL2)

Same PC and VM (Omarchy 4.5.0-3), `FATHOM_VM_DISPLAY=vnc`, driven over SSH
from the laptop, with real keys and clicks through QMP (`input-send-event`,
the usb-tablet's absolute pointer) at 1280x800. Six git projects in
`~/Work`, so Start's Recent showed five rows under the power menu. Only
`./install.sh --deck`; `check.sh` was not run.

- At 0a2d56f (before the fix): Super, the power button (948, 703), then
  Restart (830, 630) once. Start closed and Neovim opened on
  `~/Work/bravo`, the Recent row under Restart (journal:
  `xdg-terminal-exec --app-id=org.omarchy.nvim -e nvim -- /home/alan/Work/bravo`);
  no windows were open before the click.
- At eb8d811 (the fix): the same clicks. "Restart now?" showed in the menu,
  no window opened, no app launched in the next 20 s. The yes button
  (920, 661) then restarted the VM: the screen went black within 1.5 s,
  `omarchy-system reboot` was the only thing started after 17:44:40, and
  the boot id changed. The row under the menu still shows its hover
  highlight (seen on the screenshot); that's cosmetic and not changed.
- Then `~/fathom-new/uninstall.sh` (exit 0) and the six projects removed.

### 0.3.0: 20 November 2026, Windows 11 (WSL2)

Same PC and VM (Omarchy 4.5.0-3), at 8ce564e (the 0.3.0 changelog; this
commit adds only this result): `check.sh` 26 passed, 0 failed, in 81 s,
the real-ufw checks among them 15 passed, 0 failed. Then, not in
`check.sh`: `./install.sh --screensaver` (exit 0; `fathom.idle` on,
`fathom-screensaver shows` blueprint) and `uninstall.sh` (exit 0;
`omarchy.idle` on again, Blueprint and `fathom.idle` gone).

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
- Issue #10 (Care's updates list after updating), at b56b60e with the fix
  uncommitted (committed unchanged as 812c4d1), the old and new `fathom-care` copied into the VM: a check
  found 2 repo updates (aether, mise-bin). `sudo pacman -Syu` was refused by
  Omarchy's pacman hook ("Omarchy updates should normally run through:
  omarchy update"); `omarchy-update -y` upgraded both in 6 s. Then the old
  `status` still said 2; the new one said `updatesStale` and `checking`,
  its check finished within a second, and both then said 0 (`checkupdates`:
  0). Care's own update (`care-new update`) opened Omarchy's terminal, which
  waited at "Continue with update?" until a `y` was sent through QMP; the
  update ended at 06:59:10 and the new check's `checkedAt` is 06:59:10.
- Issue #11 (Blueprint as the screensaver), the working tree after 8fb1fbe
  copied into the VM (committed as 020e591): `./install.sh --screensaver` built Blueprint and
  finished in 15 s; `fathom.idle` on, `omarchy.idle` off, the clone's
  Service.qml differing from Omarchy's in the one line. With the screensaver
  at 30 s, the idle service logged idle at 07:13:18 and started
  `fathom-screensaver`; Blueprint ran fullscreen on the special workspace
  with class `org.omarchy.screensaver`, and a Shift sent through QMP closed
  it. `uninstall.sh`: `omarchy.idle` on again, Blueprint and `fathom.idle`
  gone. Switching idle services left both loaded ("Handler was registered
  but will not be used") until the shell restarted, so install and
  uninstall now restart it; after that, one service-ready and no warning
  in the new shell.

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
