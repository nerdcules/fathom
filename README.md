# Fathom

*Idea: [nerdcules](https://github.com/nerdcules) · Written by: Claude, in [Claude Code](https://claude.com/claude-code)*

A futuristic, Windows-inspired desktop layer for [Omarchy](https://omarchy.org),
built for Docker, .NET and AI work. Deep-space navy, cyan and violet, with
windows framed in a cyan-to-violet gradient.

![Fathom theme preview](theme/preview.png)

## Promo

[![Personalise changing Fathom's accent and corners, from the promo](promo/video/preview.gif)](promo/video/fathom-promo.mp4)

A 92.83-second tour: [with voiceover](promo/video/fathom-promo.mp4) or
[captions only, no sound](promo/video/fathom-promo-captions.mp4). The desktop, the desk
(Alt+Tab, Task view, Snap layouts, Quick settings) and Personalise are live
recordings from a laptop running Fathom, made on 17 November 2026. Start, the
Command Deck, Care, Sentinel, Pulse and Crumbs are the real pages drawn from
made-up data (`promo/demo-data.py`), and say so on screen. The voice is
[Kokoro](https://github.com/thewh1teagle/kokoro-onnx) (`af_heart`), run on
the same laptop. `promo/script.md` lists each line with where its claim comes
from; `promo/make.sh` builds it again.

## Install

```bash
git clone <this repo> ~/Work/fathom
cd ~/Work/fathom
./install.sh            # the theme, mini-player, Command Deck, desk and Mail
./install.sh --signin   # the sign-in screen (asks for your password)
```

| Option | What it does |
|---|---|
| `--skin` | The desktop theme, with a glassy bar: its bar, panels and menus are frosted glass, so Hyprland's blur goes on. Also `fathom-look`, which builds the theme with your look from [Personalise](#personalise) |
| `--player` | The mini-player, its keys and its bar widget |
| `--deck` | The Start menu, the Command Deck with its Care and Personalise pages, their keys, Care's check every 3 hours, and the deck's pill in the bar |
| `--desk` | Alt+Tab with window previews, Task view, Snap layouts and Quick settings, and their keys (see [Desk](#desk)) |
| `--mail` | New-mail notifications and their background service, for Outlook.com only. Adding an account is parked for now (see [Mail](#mail)), so with none added it does nothing (below) |
| `--sentinel` | Sentinel, its key and its watcher service, plus its daily file check and firewall buttons, which need your password |
| `--pulse` | Pulse, its key and its collector service. Asks for your password once if `ufw` is installed and Docker's bridge (`docker0`) has an address, so containers can reach it |
| `--opensnitch` | With `--sentinel`: also install OpenSnitch, which asks the first time each app connects somewhere new |
| `--crumbs` | Crumbs, its key, and the helper that writes the browsers' cookie rules. Needs your password for the helper |
| `--phone` | The laptop side of [Fathom for Android](#phone): `fathom-phone` and its service, and a firewall rule for port 4920. Needs your password for the rule |
| `--signin` | The sign-in screen. Needs your password |
| `--all` | Every part (OpenSnitch only with `--opensnitch`) |
| `--link` | Link the commands, their Hyprland files and the theme `fathom-look` builds from to this repo instead of copying, for working on them (theme edits show after `fathom-look apply`) |
| `--no-apply` | Install the desktop theme without switching to it |

With no part named, it installs the parts that need no password: `--skin`,
`--player`, `--deck`, `--desk` and `--mail`.

Mail is in that set, but adding an Outlook.com account needs a Microsoft
app registration, which personal accounts can't make any more (see
[Mail](#mail)). Until an account is added, the `fathom-mail` service starts
at each sign-in, logs "No mail accounts; nothing to watch." and stops; it
contacts nothing, and the deck shows no mail line. To leave Mail out, name
the other parts: `./install.sh --skin --player --deck --desk`.

Running it again updates what's installed. If that replaces a shell plugin
(the mini-player's bar widget, the deck or the desk), it restarts the Omarchy shell at
the end so the new version loads; the bar blinks once.

What you have stays until its replacement works. A shell plugin is copied
to `~/.local/state/fathom/staging` and checked with `omarchy plugin
validate` before anything of its part changes, and if Omarchy then won't
turn it on, the plugin you had goes back. The theme is built beside the one
you had; if the build fails, or Omarchy won't switch to it, the shipped
theme, the built theme folder and `fathom-look` you had go back, and so does
the theme that was on. Each part that finishes is added to
`~/.local/state/fathom/installed`. If a part fails, the install stops there
and says which parts finished in this run, which weren't done, and the
command that carries on: the parts left, with the same options. Parts that
finished stay, and running a part again is safe. Other files of the part
that failed, such as its command or Hyprland file, may already be in place;
that command finishes them, and `./uninstall.sh` removes them. If an install
is killed part-way, the next run first puts back the plugin or theme it had
moved aside.

Each install records where it came from in `~/.local/state/fathom/source`:
the clone, its commit and branch, the options and the parts installed, for
[updating](#updating).

### Updating

```bash
fathom-update                 # is there a newer Fathom, and what's in it
fathom-update apply           # install it
fathom-update rollback        # go back to the version before
```

Fathom updates from the git clone you installed it from. Versions are
releases: git tags named for [semantic versions](https://semver.org),
`vMAJOR.MINOR.PATCH`, with what changed in [CHANGELOG.md](CHANGELOG.md).
`fathom-update` follows releases and never offers a pre-release such as
`v0.2.0-rc1`; `fathom-update channel main` follows every commit on the
branch instead (`channel releases` goes back).

`fathom-update` (or `check`) fetches from the clone's remote and says what's
new: the commits, the parts they touch, and whether reinstalling them needs
your password. That `git fetch` is the only thing it sends; `fathom-update
status` shows the last answer without going online. `apply` fetches again,
moves the clone forward only if it can do so cleanly (`git merge
--ff-only`), and runs `install.sh` again, with your options, for the parts
whose files changed (all of them if `install.sh` changed), so a password is
asked for only when a part that installs something as root changed. Your
own uncommitted changes or commits in the clone stop it, and it says so.
`rollback` moves the clone back to the version before the last `apply` and
reinstalls the parts that differ.

Care can look for you: `fathom-update auto on` adds the check to Care's
3-hourly one (off unless you turn it on, since it contacts the remote), and
Care's Updates card then shows Fathom's version and changes with an
**Update Fathom** button. Its settings are in `~/.config/fathom/update.json`.

### What needs your password

Everything not listed here runs as you. `install.sh`, `uninstall.sh` and
Care run a command as root with `sudo` when started from a terminal and
with `pkexec` (a polkit password prompt) otherwise; Sentinel and Crumbs use
`pkexec`.

| Part | When | What runs as root, and what it does |
|---|---|---|
| `--skin`, `--player`, `--desk`, `--mail` | Never | Nothing |
| `--sentinel` | `install.sh` | `sentinel/install-root.sh install`: copies `admin` and `check-files` to `/usr/local/lib/fathom-sentinel/`, and `fathom-sentinel-files.service` and `.timer` to `/etc/systemd/system/`; runs `systemctl daemon-reload`, enables and starts the timer, and starts the first file check |
| | `install.sh --opensnitch` | Also `pacman -S --needed --noconfirm opensnitch` if OpenSnitch isn't installed (noting that Fathom installed it), then `systemctl enable --now opensnitchd.service` whether or not it was |
| | Daily, from the timer | `check-files`: `pacman -Qkk`, read-only and offline (see [Sentinel](#sentinel)); writes `/var/lib/fathom-sentinel/integrity.json` |
| | **Lockdown**, **Block**, **Unblock** | `pkexec /usr/local/lib/fathom-sentinel/admin`: `ufw prepend` or `ufw delete` of Fathom's own rules only |
| | **Check files now** | `systemctl start fathom-sentinel-files.service`, a system service, which systemd authorises through polkit |
| | `uninstall.sh` | `sentinel/install-root.sh uninstall`: stops and disables the timer, deletes its two units and runs `systemctl daemon-reload`; removes Fathom's firewall rules; if Fathom installed OpenSnitch, stops it and runs `pacman -Rns --noconfirm opensnitch`; deletes `/usr/local/lib/fathom-sentinel` and `/var/lib/fathom-sentinel` |
| `--pulse` | `install.sh` | `ufw allow proto tcp from 172.16.0.0/12 to <docker0's address> port 4317,4318 comment fathom-pulse`, only if `ufw` is installed, `docker0` has an IPv4 address and no rule for this is there already (Fathom's or yours) |
| | `uninstall.sh` | `ufw delete` of that rule, with its comment, if `install.sh` recorded its address |
| `--crumbs` | `install.sh` | `crumbs/install-root.sh install`: copies `policy` to `/usr/local/lib/fathom-crumbs/`. If this fails, Crumbs is installed anyway and can't block |
| | **Apply**, and `fathom-crumbs apply`, `block`, `unblock` and `clear` | `pkexec /usr/local/lib/fathom-crumbs/policy`: writes or deletes `fathom-crumbs.json` in each installed browser's managed-policy folder under `/etc`, creating the folder if needed |
| | `uninstall.sh` | `crumbs/install-root.sh uninstall`: `policy clear`, then deletes `/usr/local/lib/fathom-crumbs` |
| `--deck` | `install.sh`, `uninstall.sh` | Nothing |
| | Care: freeing old package downloads | `paccache -rk1` |
| | Care: freeing system logs | `journalctl --vacuum-size=200M` |
| | Care: restarting a failed system service | `systemctl restart <that unit>` |
| Any | `fathom-update apply` and `rollback` | Whatever `install.sh` runs as root for the parts being reinstalled, as above; nothing else |
| `--phone` | `install.sh` | In one call: `ufw allow proto tcp from <range> to any port 4920 comment fathom-phone` for each of 192.168.0.0/16, 10.0.0.0/8 and 172.16.0.0/12, and `ufw allow in on tailscale0 to any port 4920 proto tcp comment fathom-phone` if there's a `tailscale0`; only for rules not there already (Fathom's or yours), and only if `ufw` is installed |
| | `uninstall.sh` | In one call, `ufw delete` of each of those rules, with its comment, if any rule carries Fathom's comment |
| `--signin` | `install.sh` | `signin/install-root.sh install`: copies the theme to `/usr/share/sddm/themes/fathom` (owned by root) and writes `/etc/sddm.conf.d/99-zz-fathom.conf`, which selects it |
| | `uninstall.sh` | `signin/install-root.sh uninstall`: deletes both |

`uninstall.sh` runs each root step only when it finds that part installed
(the folder in `/usr/local/lib`, the SDDM theme or its file, or Pulse's
recorded address).

### Uninstall

`./uninstall.sh` takes out what `install.sh` added, part by part, for each
part it finds:

- **Theme:** if Fathom's theme is on, it switches to the theme `install.sh`
  recorded as on before Fathom's (Tokyo Night if none was recorded). If the
  bar is still glassy and `install.sh` recorded it as `opaque` or `none`
  before, it goes back to that.
  It deletes `~/.config/omarchy/themes/fathom` if Fathom built it (a
  `fathom` theme it didn't make is left), `~/.local/share/fathom/theme` and
  `~/.local/bin/fathom-look`.
- **Fathom's block in `hyprland.lua`** goes first, and Hyprland reloads,
  while the files it loads are still there: deleting them first sometimes
  froze Hyprland in the test VM (see `tests/vm/README.md`).
- **Each part:** stops it, turns its shell plugin off, and deletes its
  command in `~/.local/bin`, its file in `~/.config/hypr`, its plugin in
  `~/.config/omarchy/plugins`, its user services and timer, and its files in
  `~/.local/share/fathom`. The root parts go as in the table above.

These settings and sign-ins of yours are deleted, and Fathom keeps no copy:

- `~/.config/fathom/update.json`: `fathom-update`'s channel and whether
  Care looks for updates (always), with `~/.local/bin/fathom-update`.

- `~/.config/fathom/look.json`: your look from Personalise (always, even if
  `--skin` wasn't installed).
- `~/.config/fathom/start.json`: Start's pins (with the deck).
- `~/.config/fathom/mail.json`: Mail's accounts and client IDs, and every
  keyring entry Fathom Mail saved (`secret-tool clear application
  fathom-mail`), which are its sign-ins (with Mail).
- `~/.config/fathom/phone.json`: the phones paired with Fathom (with the
  phone service); its key and certificate go with `~/.local/state/fathom`.
- `~/.config/fathom/sentinel.json`: the devices you marked as yours (with
  Sentinel).
- `~/.local/state/fathom`, all of it: Care's measurements and disk history,
  Sentinel's events and the devices it has seen, Pulse's saved map, Mail's
  recent messages, and what `install.sh` recorded (the theme and bar to go
  back to, the parts installed, Pulse's address).

It leaves:

- The backups `install.sh` made: `hyprland.lua.bak.<time>` in
  `~/.config/hypr`, and `fathom.bak.<time>` in `~/.config/omarchy/themes` if
  a `fathom` theme of yours was moved aside.
- Packages you installed for Fathom (mpv, the Pulse Python packages and so
  on), and OpenSnitch if it was installed before Fathom; if `--opensnitch`
  turned its service on, it stays on.
- The browser policy folders Crumbs created under `/etc`: only its own file
  in them is deleted.
- Firewall rules that aren't Fathom's, including one with a Fathom comment
  but another shape, which it names.
- What you did with Fathom: cookies **Forget** deleted, what Care freed,
  restarted or updated, settings changed in Quick settings, the bar and
  wallpaper chosen in Personalise (Omarchy's own settings), containers
  started or stopped, and the boot unlock logo if you chose Fathom's in
  Omarchy's menu (*Default* there puts Omarchy's back).

## What's here

```
theme/          The Omarchy desktop theme: colours, window corners,
                wallpapers, icons, preview, boot unlock logo and its
                preview
signin/fathom/  The sign-in screen, an SDDM theme in QML
signin/install-root.sh
                Run as root: copies the sign-in theme and selects it (every
                root step is in "What needs your password", above)
player/bin/fathom-player
                The mini-player command (plays and controls mpv)
player/hypr/    Its window rules and keys
player/plugin/fathom.player/
                Its bar widget
deck/bin/fathom-deck
                The Command Deck's command: reads the machine as JSON and
                starts, stops and restarts containers
deck/hypr/      Its key and blur
deck/plugin/fathom.deck/
                The deck itself, an Omarchy shell panel: the Deck, Care,
                Sentinel and Pulse pages and the Start menu, and its pill
                in the bar (DeckBar.qml)
desk/bin/fathom-desk
                The desk's command: opens its views, reads windows and
                Quick settings' state as JSON, and changes settings
desk/hypr/      Its keys, and Alt+Tab's handling of Tab and Alt
desk/plugin/fathom.desk/
                The desk itself, an Omarchy shell panel kept loaded:
                Alt+Tab, Task view, Snap layouts and Quick settings
look/bin/fathom-look
                Personalise's command: keeps your look and builds the theme
                folder Omarchy reads from theme/ with it
update/bin/fathom-update
                Checks for, installs and rolls back Fathom updates; comes
                with every install
CHANGELOG.md    What changed in each release
start/bin/fathom-start
                The Start menu's command: recent projects, pins, asking
                Claude Code, Focus mode and power
care/bin/fathom-care
                Care's command: measures the disk, finds failed services
                and updates, and cleans up
care/systemd/   The timer that runs Care's check every 3 hours
mail/bin/fathom-mail
                Mail's command (Python, standard library only)
mail/fathom_mail/
                Its package: core.py (keyring, HTTP, notifications) and one
                module per mail service (outlook.py)
mail/systemd/   The service that watches for new mail
sentinel/bin/fathom-sentinel
                Sentinel's command and watcher (Python, standard library only)
sentinel/fathom_sentinel/
                detect.py: turns journal lines, neighbours and file checks
                into events
sentinel/root/  The root parts: admin (the firewall buttons, run through
                pkexec) and check-files (the daily file check)
sentinel/systemd/
                The watcher (a user service) and the file check's service
                and timer (system)
sentinel/install-root.sh
                Installs and removes the root parts
phone/bin/fathom-phone
                The phone's laptop side: an HTTPS service on port 4920 that a
                paired phone reads the deck from, and pairing by QR code
phone/systemd/  Its user service
crumbs/bin/fathom-crumbs
                Crumbs' command: reads every browser's cookies and history
                (from copies) as JSON, and forgets cookies
crumbs/root/policy
                The root part, run through pkexec: writes Fathom's cookie
                rules into each browser's managed-policy folder
crumbs/install-root.sh
                Installs (or removes) that helper
crumbs/hypr/    Its key
promo/          The promo: script.md (shots, voiceover and their sources),
                take.sh (records the live takes; it takes over the screen
                for about a minute and puts everything back), demo-data.py,
                Scene.qml and Card.qml (the rendered shots), voice.py,
                assemble.py and make.sh; video/ holds the two cuts
crumbs/demo/    make-preview.sh, which draws crumbs/preview.jpg from made-up
                browsing (make-demo.py) rendered by the real page (Preview.qml)
pulse/bin/fathom-pulse
                Pulse's command and collector
pulse/fathom_pulse/
                otlp.py: the OTLP receivers and decoding; store.py: the last
                hour of spans, the day's summaries and the map built from them;
                agents.py: Claude Code's day, from its session files
pulse/systemd/  The collector (a user service)
pulse/hypr/     Its key
art/            make-art.py, which draws the wallpapers, preview and logo
tests/          node --test tests/ && python3 -m unittest discover -s tests
tests/vm/       The same, for real, in a disposable Omarchy VM: install,
                upgrade, uninstall and the firewall buttons (README there)
install.sh      Installer
uninstall.sh    Remove what the installer added (see "Uninstall", above)
```

## Mini-player

Copy a YouTube (or any [yt-dlp](https://github.com/yt-dlp/yt-dlp)-supported)
link and press **Super+Alt+Y**. It plays in a 640×360 window pinned to the
bottom-right corner, above everything and on every workspace, without taking
focus from what you're doing. Press Super+Alt+Y with another link copied to
switch to it. **Super+Ctrl+Y** closes it.

While it plays, the bar shows the title. Click it to pause, scroll to skip,
middle-click to mute and right-click to close. Your keyboard's media keys work
too (through `mpv-mpris`).

From a terminal or script:

```bash
fathom-player play https://www.youtube.com/watch?v=...
fathom-player toggle | back 10 | forward 10 | mute | stop | status
```

Video is capped at 720p to spare the battery; set `FATHOM_PLAYER_MAX_HEIGHT`
to change that. It decodes on the GPU where it can, and picks another codec
over AV1 when one is offered, since GPUs without AV1 decoding (such as the
Surface Laptop 3's) leave AV1 to the CPU. It needs `mpv`, `yt-dlp`, `socat`,
`jq` and `wl-clipboard`, all on Omarchy already.

Installing adds `~/.local/bin/fathom-player`, `~/.config/hypr/fathom-player.lua`,
three marked lines at the end of `~/.config/hypr/hyprland.lua` (after a
backup), and the `fathom.player` bar widget.

## Start menu

![Fathom Start menu](start/preview.jpg)

**Tap Super** on its own for Start, as on Windows. Super with any other key
works as before. Tap Super again or press Esc to close it.

- **Search or ask.** Type to find apps, recent projects and actions (the
  deck, Care, Focus mode, lock, sleep, restart and so on): ↑ ↓ and Enter, or
  click. Initials work too: *vsc* finds Visual Studio Code. The last rows
  always offer to **ask Claude Code** what you typed, in a terminal, either in
  your home folder or in your most recent project. Nothing is sent anywhere
  until you choose that; the suggestions under the search box ask the same
  way.
- **Pinned:** your terminal, editor, the Command Deck, Care, browser and
  Files to start with. Right-click any app (here or under **All apps**) to pin
  or unpin it.
- **Recent work:** the git projects in `~/Work`, `~/Projects` and similar
  folders you touched last, with what they're built with, the branch (`*`
  for uncommitted changes) and when. Click one to open it in your editor, or
  hover for a terminal there, Claude Code there, or Files.
- **Along the bottom:** whether Docker is running (click for the deck),
  **Focus** (Omarchy's do-not-disturb), **About Fathom** (the ⓘ button, or
  search "about"; Esc closes it), and power: lock, sleep, sign out,
  restart, shut down. The last three ask first.

Pins and suggestions are kept in `~/.config/fathom/start.json`.

```bash
fathom-start                    # open or close it
fathom-start menu | jq .        # what it shows, as JSON
fathom-start pin obsidian       # pin an app by its desktop id
```

## Desk

Windows' ways of handling windows, on Hyprland. Install it with `--desk`
(it's one of the parts installed by default).

| Key | What it does |
|---|---|
| **Alt+Tab** | Switch windows |
| **Super+Tab** | Task view: every window and workspace |
| **Super+Z** | Snap layouts for the focused window |
| **Super+Alt+A** | Quick settings |

**Alt+Tab** shows every window as a card with a live picture of it, most
recently used first, with the window you used before this one picked. Tab
again (Alt still held) steps on, Shift+Tab or the arrow keys step back and
around, and letting go of Alt brings the picked window forward, switching
workspace if it's on another. Esc leaves things as they were. Windows
minimized to Omarchy's dock are in the list too; picking one brings it back
to the workspace it left. Scratchpads aren't. It replaces Omarchy's Alt+Tab,
which moved to the next window without showing anything.

**Task view** shows the windows of the workspace on screen as large live
cards, and every workspace along the bottom. Hover a workspace to see its
windows, click one to go there, or click New for an empty one. Click a
window to bring it forward, drag it onto a workspace to move it there, or
close it with its × (or a middle-click, or Delete). Page Up and Page Down
look at the other workspaces; 1 to 9 go to one. Task view takes Super+Tab,
which was Omarchy's "next workspace"; Super+Shift+Tab (previous) and
Super+Ctrl+Tab (the one before) are unchanged.

**Snap layouts** offers six layouts for the focused window: halves, two
thirds and one third, thirds, one big and two stacked, quarters, and centre.
Hover a zone to see where the window would go, at full size, and click to
put it there; the arrow keys and Enter work too. Then, as on Windows, Snap
assist offers the workspace's other windows for the zones left; Esc stops.
A snapped window floats at the zone's size, with the same gaps tiling
leaves, so this works on tiled workspaces as well as floating ones. **Back to
tiling** puts it back in the tiling.

**Quick settings** opens under the bar at the top right: Wi-Fi, Bluetooth,
Focus (Omarchy's do-not-disturb), night light, stay awake and the power
profile as tiles, volume and brightness as sliders, and the battery, Lock and
Omarchy's menu along the bottom. The arrows on Wi-Fi and Bluetooth open
Omarchy's own panels for choosing a network or a device.

The desk's panel stays loaded in the shell so Alt+Tab opens without waiting.
It reads the windows (`fathom-desk state`: 64 to 72 ms over five runs here)
when a view opens and again as windows open, close and move while one shows;
Quick settings reads its state (`fathom-desk settings`: 565 to 623 ms over
three runs) on opening and every 4 seconds while it shows. Nothing is read
while nothing shows.

Alt+Tab is driven from Hyprland: while the switcher is up, Hyprland is in a
submap called `fathom-switch`, so Tab reaches the switcher and nothing else.
If nothing happens for 8 seconds it leaves the submap by itself, so the
keyboard can't be left there.

```bash
fathom-desk tasks | snap | quick       # open or close a view
fathom-desk state | jq .               # windows, workspaces and monitors
fathom-desk settings | jq .            # what Quick settings shows
fathom-desk set brightness 40          # also wifi, focus, nightlight, awake on|off; profile <name>
```

Installing adds `~/.local/bin/fathom-desk`, `~/.config/hypr/fathom-desk.lua`
(loaded from Fathom's marked block in `hyprland.lua`) and the `fathom.desk`
shell plugin. Uninstalling removes them, and Hyprland's reload puts Omarchy's
own Alt+Tab and Super+Tab back.

## Command Deck

![Fathom Command Deck](deck/preview.jpg)

Press **Super+Alt+D** for a glass overlay showing your dev machine at a glance.
Press it again, or Esc, or click outside the cards, to close it.

- **System:** CPU, GPU, memory and each disk. A disk over 85% full turns amber,
  over 95% red. It also shows how much space Docker's images, build cache and
  volumes take, since that's usually where a disk goes.
- **Containers:** every Docker container, grouped by Compose project, with its
  ports, CPU and memory. Red means unhealthy or crashed. Hover a row to start,
  stop or restart it, or to follow its logs in a terminal. The lazydocker
  button opens lazydocker.
- **.NET:** the installed SDK and the .NET apps running now (`dotnet run`,
  `dotnet watch`, AppHosts and other apps), with CPU and memory. Language
  servers and build nodes are counted in one line rather than listed.
- **AI:** the coding agents running (Claude Code, Codex, Gemini CLI, opencode,
  Aider and others), which project each is in, and whether it's working or
  idle. Claude Code says which itself (the status it keeps in
  `~/.claude/sessions/`); the others count as working while they use 3% or
  more of a CPU core. If Ollama is running, its loaded models and their VRAM.

Above the cards, a summary line puts whatever needs attention first.

The deck reads the machine only while it's open, every few seconds, and only
locally; the one network call is to Ollama on `127.0.0.1`.

### In the bar

A small pill after the workspaces shows what's worth a glance without opening
the deck, each part only when it has something to say:

- containers that need attention (red), or how many are running;
- Care's warnings (red) and a disk over 85% full (amber; red over 95%);
- Sentinel's alerts from the last day (amber);
- coding agents working (cyan), or how many are idle.

With nothing to say it shows the deck's mark alone. Click it for the deck
page with the worst news, right-click for the deck, middle-click for Start;
hover for the details.

Unlike the deck, the pill reads in the background: `fathom-deck brief` every
10 seconds (set `interval` on its entry in `~/.config/omarchy/shell.json`).
That asks Docker for its container list, asks Care and Sentinel only what
they already know, and samples CPU for 0.4 s only when an agent other than
Claude Code is running. On this machine it took 849 to 927 ms per run, most
of it that sample, with Codex running (three runs, 2026-11-15).

From a terminal:

```bash
fathom-deck status | jq .                # what the deck shows, as JSON
fathom-deck brief | jq .                 # what the bar's pill shows
fathom-deck container restart <name>     # also start, stop
fathom-deck logs <name>
```

Installing adds `~/.local/bin/fathom-deck`, `~/.config/hypr/fathom-deck.lua`
(loaded from the same marked block in `hyprland.lua` as the mini-player) and
the `fathom.deck` shell plugin, which also puts the pill in the bar's left
section.

## Care

![Fathom Care](care/preview.jpg)

Care is the deck's second page: **Super+Alt+C**, or Ctrl+Tab while the deck
is open. It looks after the machine so you don't have to.

- **Disk:** what fills it (system, Docker, AI models, caches, projects, the
  rest of your home folder), how long until it's full at the current rate
  (once it has a few days of history), and what's **safe to free**: the trash,
  Docker's build cache and images no container uses, the NuGet, npm, uv and
  pip caches, AUR build files, old package downloads and old system logs. Each
  says what happens if you free it, and Care asks before deleting anything.
  Old package downloads and system logs need your password, so the deck
  closes for those and a notification says how much was freed.
- **Warnings:** failed services (yours and the system's), with buttons to
  restart one or read its log, a disk over 85% full, and a kernel update
  waiting for a restart. Below them: battery health, CPU temperature, when you
  last updated and whether snapshots are on.
- **Updates:** system packages (flagging a new kernel), AUR packages, firmware
  and Omarchy itself, with the download size. **Update everything** runs
  Omarchy's own updater in a terminal, which checks free space, takes a
  snapshot, updates, and verifies the system still boots.

A systemd user timer runs Care's check every 3 hours, and you get a
notification when something new needs you: a service fails or the disk passes
85% or 95%. The check asks the package mirrors, the AUR and fwupd what's new,
as Omarchy's own update check does, and with `fathom-update auto on` Fathom's
git remote what's new in Fathom; nothing else leaves the machine. To turn
the timer off: `systemctl --user disable --now fathom-care.timer`.

```bash
fathom-care status | jq .     # what Care shows, as JSON
fathom-care check             # check now
fathom-care clean trash npm   # free those (names from `status`)
```

## Sentinel

Sentinel is the deck's third page: **Super+Alt+X**, or Ctrl+Tab from Care. It
keeps watch over the machine and tells you when something needs you. Install
it with `./install.sh --sentinel` (it asks for your password).

A user service, `fathom-sentinel.service`, follows the system journal, looks at
the network every 30 seconds, and reads OpenSnitch's rules and the file
check's results every minute. It runs as you. What it watches:

- **Firewall blocks** (ufw). Ordinary blocked chatter is counted, and the 4
  addresses blocked most today are listed, ones from the internet first. 12 or
  more different ports blocked from one address within 5 minutes is reported
  as a port scan, at most once an hour per address. UDP from a high port to
  one of this machine's own reply ports (32768 to 60999 by default) doesn't
  count towards that: it's an answer the firewall couldn't match, such as a
  TV or broadband hub replying to a discovery broadcast, not a probe.
- **Sign-ins and sudo.** A failed SSH sign-in is reported at once. A single
  wrong password is listed; 3 within 10 minutes is a warning. Each sudo
  command is listed.
- **USB storage** being plugged in.
- **Devices on your network.** On a network it hasn't seen before, it spends
  the first 10 minutes learning what's there and trusts those devices. After
  that, a new device is a warning until you mark it as yours. Devices not seen
  for 60 days are forgotten.
- **System files.** A root timer, `fathom-sentinel-files.timer`, runs
  `pacman -Qkk` once a day and records which files no longer match their
  package. A changed timestamp alone doesn't count. The first check sets the
  baseline; after that, only new differences are reported. The service is
  sandboxed: it can read every file but not change any, and it has no network.
  It reads every installed file, so its disk cache is held to 1 GiB
  (`MemoryHigh=1G`) rather than growing to the size of your installed
  packages (16.2 GB once here) and crowding other programs' cache.
- **OpenSnitch**, if installed: its rule counts, and new rules as they appear.

Warnings, port scans, failed SSH sign-ins and USB storage send a notification;
clicking it opens Sentinel. Events found while catching up on the journal
(after a restart, say) show in the deck without notifications.

The page's buttons: **Lockdown** blocks every new incoming connection on
Wi-Fi, wired and mobile interfaces (not loopback, Docker or VPNs), SSH into
this machine included: in the test VM (`tests/vm`), the SSH session that
turned lockdown on carried on, and the next connection timed out; block or
unblock an address; trust or forget a device; check files now; and open the
firewall, sign-in or file-check log. The firewall buttons run a fixed root
script, `/usr/local/lib/fathom-sentinel/admin`, through pkexec, and it checks
every argument. Nothing leaves the machine.

A firewall rule is Fathom's only if it carries Fathom's comment
(`fathom-lockdown` or `fathom-block`) and has exactly the shape the buttons
add: `deny in on <interface>` or `deny from <address>`, IPv4 and IPv6.
Ending lockdown, unblocking and `uninstall.sh` remove only those, each by its
full description with the comment and never by rule number, and check the
rule files afterwards: every other rule stays, even one that differs from
Fathom's only by its comment. Pressing Lockdown or Block again adds nothing.
If a rule of yours matches the one Fathom would add apart from its action
or comment, ufw would skip Fathom's, so Lockdown and Block change nothing and
name your rule instead; a notification says why.

```bash
fathom-sentinel status | jq .        # what Sentinel shows, as JSON
fathom-sentinel trust <mac>          # mark a device as yours
fathom-sentinel lockdown on          # asks for your password
fathom-sentinel log firewall         # today's blocks, in a terminal
```

It needs `ufw`, `jq`, `iw` and `ip`. `--opensnitch` also installs OpenSnitch
and starts its window, which asks the first time each app connects somewhere
new. `uninstall.sh` removes the firewall rules Sentinel's buttons added, and
removes OpenSnitch only if Fathom installed it. A rule with Fathom's comment
but another shape may be yours, so it is left and named.

## Pulse

Pulse is the deck's fourth page: **Super+Alt+P**, or Ctrl+Tab from Sentinel.
It draws your stack as a map of what calls what, from the traces your apps
send with OpenTelemetry. Install it with `./install.sh --pulse`; it needs
`python-opentelemetry-proto`, `python-grpcio` and `python-protobuf`
(`omarchy pkg add python-opentelemetry-proto python-grpcio python-protobuf`).

A user service, `fathom-pulse.service`, listens where OpenTelemetry exporters
send by default: **4317** (OTLP over gRPC) and **4318** (OTLP over HTTP,
protobuf or JSON), on `127.0.0.1`, `::1` and Docker's bridge address. It keeps
traces and drops metrics and logs, so an app that exports all three doesn't
log errors.

- **The map.** Each service that sends traces is a box, with its requests per
  second or minute and its p95. A call from one service to another is a line.
  When a service calls something that sends no traces of its own, such as a
  database, a cache, a message queue, Ollama or an outside API, Pulse adds a
  box for it from what the calling span says (`db.system`, `server.address`,
  `gen_ai.system`, `peer.service` and so on), marked *seen from its callers*.
  A box and its line turn amber when there are errors and red at 5% or more.
- **The inspector.** Click a box for its requests, p95 and errors, its 3
  busiest operations, what calls it and what it calls (click those to move
  along), and its most recent errors (up to 4). **Ask Claude about this** opens
  Claude Code in a terminal with those figures and asks what could be wrong.
  The figures go in as data, quoted and cut to one short line each, since any
  app that can reach the ports can name its services anything.
- **15 min, 1 hour, 24 hours.** The last hour comes from the spans themselves,
  up to 100,000 of them in memory (the oldest go first). The day comes from
  per-minute summaries, saved to `~/.local/state/fathom/pulse.json` every 5
  minutes and when the service stops, so a restart keeps them. A p95 over 24
  hours is read from those summaries and can be up to 25% high; the page says
  so.

Nothing leaves the machine, and nothing is sent to Claude unless you click
**Ask Claude about this**. Pulse doesn't edit your projects: point them at it
as below.

### Agents today

Under the map, one row per project shows when Claude Code worked on it
today and when it waited for you:

- **The bar** runs from the start of the hour of the day's first work to now. Blue is
  working: from your prompt until Claude's turn ends, including the
  commands it runs. Amber is waiting for you: from the end of its turn until
  your next prompt. A gap is idle: nothing for over 10 minutes, whatever it
  was doing.
- **The dot** is the state now. While Claude Code runs, it notes in
  `~/.claude/sessions/` whether each session is busy or idle; Pulse trusts
  that note only when its process is still running with the same start
  time. A busy session is working, and its bar runs to now even through a
  long, silent command. An idle one is waiting for you: the header says so
  ("Claude is waiting for you in shop") and the inspector says since when.
  A closed session is idle.
- **Click a row** for the project's day: time working and waiting, your
  prompts, Claude's edits (and to how many files), its commands (and how
  many ran tests), its output tokens, and its sessions with Claude Code's
  title for each.

A step counts toward the git repository it ran in; a step outside any
repository counts toward the project its session started in. The 5 most
recent projects are shown.

It reads Claude Code's session files in `~/.claude/projects` (or
`$CLAUDE_CONFIG_DIR`), only the lines added since the last read, and keeps
an index in `~/.local/state/fathom/agents.json`, readable only by you. It
reads timestamps, folders, git branch, model, token counts, tool names, the
paths of edited files and the session titles. Commands are matched for test
runners (`dotnet test`, `pytest`, `node --test` and the like) and then
dropped, never kept. The text of Claude's replies isn't read; of your messages, only
the first 40 characters are looked at, to tell your prompts from notes
Claude Code adds itself (a slash command, a background task's notice), and
none of it is kept. It needs no service: the card works whether or not the collector is running.
Other agents (Codex, opencode) aren't read yet.

### Pointing a .NET app at Pulse

Add the OTLP exporter to the app's tracing:

```bash
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
dotnet add package OpenTelemetry.Extensions.Hosting
dotnet add package OpenTelemetry.Instrumentation.AspNetCore
dotnet add package OpenTelemetry.Instrumentation.Http
```

```csharp
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService("orders-api"))
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter());
```

With no endpoint set, .NET's exporter sends over gRPC to `localhost:4317`,
which is Pulse. (Checked with a console app using the same `AddOtlpExporter()`
call and no endpoint; the web setup above follows Microsoft's
[OTLP example](https://learn.microsoft.com/dotnet/core/diagnostics/observability-otlp-example).)
An app that already reads the endpoint from configuration, such as one using
Aspire's ServiceDefaults, takes it from `OTEL_EXPORTER_OTLP_ENDPOINT`:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 OTEL_SERVICE_NAME=orders-api dotnet run
```

**In a container**, `localhost` is the container itself. Use Docker's bridge
address (`172.17.0.1` unless you've changed it) or give the container
`host.docker.internal`:

```yaml
services:
  api:
    environment:
      OTEL_EXPORTER_OTLP_ENDPOINT: http://host.docker.internal:4317
    extra_hosts:
      - host.docker.internal:host-gateway
```

Omarchy's firewall blocks containers from the host, so `--pulse` adds one ufw
rule: TCP 4317 and 4318, from Docker's `172.16.0.0/12` range, to the bridge
address only. A Docker network outside `172.16.0.0/12` isn't
covered. `uninstall.sh` removes the rule, naming its comment
(`fathom-pulse`) so that ufw leaves a rule of yours that differs only by
its comment.

```bash
fathom-pulse                     # open the page
fathom-pulse status 1h | jq .    # the map over 15m, 1h or 24h, as JSON
fathom-pulse agents | jq .       # Claude Code's day, as JSON
journalctl --user -u fathom-pulse    # where it's listening, or why it can't
```

If something else already has 4317 or 4318 (the standalone Aspire dashboard,
say), Pulse says so on its page and in its log, and tries again every minute.

## Crumbs

![Crumbs, showing made-up browsing](crumbs/preview.jpg)

*Made-up browsing: invented `.example` sites and well-known tracker domains,
put through the real `fathom-crumbs` and drawn by the real page
(`crumbs/demo/make-preview.sh`). Nothing in it comes from a real browser.*

Crumbs is the deck's page for cookies: **Super+Alt+O**, Ctrl+Tab from
Pulse, or search Start for "cookies". It reads every browser here that
keeps cookies: Microsoft Edge, Chromium, Chrome and Brave (each profile),
and Firefox and LibreWolf.

- **Who follows you where:** a map from sites you visited to the cookies
  they led to, trackers first. A solid line is exact: the browser stored the
  cookie under that site (a partitioned cookie). A dashed line is likely:
  the cookie was set within 5 seconds of a visit to that site, when its own
  site wasn't being visited. Another tab at the same moment can make a
  dashed line that isn't real. Hover a box to light up its lines; click a
  tracker for its cookies.
- **Domains:** every domain with cookies, as the site's registrable domain
  (ads.example.co.uk counts as example.co.uk), with the company behind it,
  what kind of tracker it is, how many sites led to it, and whether you ever
  visited it yourself. Which domains are trackers comes from Microsoft Edge's
  own tracking prevention lists, read from Edge's folder when Edge is
  installed (advertising, analytics, social, fingerprinting, cryptomining,
  and embedded content, which Edge blocks only in its Strict mode), or else
  from a short list in `fathom-crumbs`.
- **Cookies:** each cookie of the chosen domain: its name, what well-known
  ones are for (41 names, such as Google Analytics' `_ga`, Microsoft's
  `MUID` and Meta's `_fbp`), where it's sent, which browser has it, when it
  expires, its Secure, HttpOnly and SameSite flags, the site it's kept for
  if partitioned, and its size. Values stay encrypted by the browser;
  Crumbs never reads them. **Forget** deletes a domain's cookies from a
  browser that's closed (a running one would write them back).
- **Protection:** block third-party cookies, set Edge's tracking prevention
  (Basic, Balanced or Strict), and block chosen domains. These wait until
  **Apply**, which asks for your password: they're written as browser
  policy (`fathom-crumbs.json` in `/etc/opt/edge/policies/managed`,
  `/etc/chromium/policies/managed` and the like, for the browsers
  installed). Browsers then say they're managed by your organisation, and
  take the rules up when they restart, or at once from `edge://policy` or
  `chrome://policy` (Reload policies). A rule that would only allow is never
  written, so your browser's own settings stay yours. Firefox's cookies are
  shown, not blocked: Firefox keeps all its policy in one shared file.

It reads copies of the browsers' files when the page opens and 15 seconds
after each reading while it stays open; on this laptop one reading of Edge (510 cookies) and Chromium (53)
took 110 ms (2026-11-17, one run). Nothing is sent anywhere.

```bash
fathom-crumbs                               # open Crumbs
fathom-crumbs status | jq .totals           # cookies, domains, trackers
fathom-crumbs cookies doubleclick.net | jq  # one domain's cookies
fathom-crumbs block doubleclick.net         # asks for your password
fathom-crumbs apply --third-party on --prevention strict --block demdex.net
fathom-crumbs clear                         # take Fathom's rules out
```

## Phone

The laptop side of [Fathom for Android](https://github.com/nerdcules/fathom-android),
a home screen for your phone in Fathom's look. Install it with
`./install.sh --phone`, then pair a phone once:

```bash
fathom-phone pair        # shows a QR code for 2 minutes; scan it in the app
fathom-phone devices     # the phones paired
fathom-phone unpair <id> # forget one; its token stops working
fathom-phone alerts      # what a phone would be told about now, as JSON
fathom-phone test-alert  # a test alert for 10 minutes, to check notifications
```

`fathom-phone` runs as a user service and answers HTTPS on port 4920 with a
certificate it made itself. The QR code carries the laptop's addresses (Wi-Fi
or wired first, then Tailscale's), the certificate's SHA-256 fingerprint and
a one-time secret: the phone connects only to a laptop showing that
certificate, and proves the secret to be given its own token. The window
closes after 2 minutes, after one pairing, or after 5 wrong secrets. Fathom
keeps only each token's SHA-256 (`~/.config/fathom/phone.json`, readable by
you alone). A 6-digit code isn't used: on a network someone else can watch,
all million codes could be tried against what they saw.

A paired phone can read what the deck shows: Deck, Care, Sentinel, Pulse
and Claude Code's day, Crumbs, the Fathom update and your look. It also reads
the alerts `fathom-phone` works out from those: a failed service, a disk
filling up, a restart to finish an update, a container restarting or
unhealthy, Sentinel's warnings from the last 24 hours (minus devices you've
since trusted), errors in Pulse, Claude Code waiting for you and a Fathom
update. Each alert keeps the same id while it's true, so the phone notifies
once. The phone checks about every 15 minutes, the shortest Android allows
an app in the background.

Some alerts offer an action, and those are the only changes a phone can
make: trust a new device (`fathom-sentinel trust`), restart a failed service
(`fathom-care restart`), block an address (`fathom-sentinel block`). The
phone names the alert and the action; the arguments come from the laptop's
own copy of that alert, so a phone can't pass its own. Blocking and
restarting a system service need root, so they ask for your password on the
laptop. Each action is written to the service's journal (`journalctl --user
-u fathom-phone`). The laptop announces itself on
the home network as `_fathom._tcp` (Avahi) so the phone can find it when its
address changes. The firewall rule lets in only the private address ranges
home networks use, and Tailscale; Sentinel's lockdown blocks the phone like
everything else. Nothing is sent anywhere: the phone asks, the laptop
answers.

## Mail

Once an account is added (see below), new mail in your Outlook.com inbox
shows up as a notification within a minute: the sender, the subject and the
first line. Click it to open the message in Outlook on the web. Several at once become one notification. Only
your Focused inbox notifies, like Outlook's own app; set `"focusedOnly":
false` for the account in `~/.config/fathom/mail.json` to include Other. The
deck's summary line shows how many unread emails you have.

Gmail and IMAP accounts can come later: each mail service is one module in
`mail/fathom_mail/`.

### Adding your Outlook.com account

**Parked for now.** Microsoft only lets a program read Outlook.com mail
through an *app registration*, and personal accounts (live.com, outlook.com,
hotmail.com) can no longer create one: the Azure portal accepts only work or
school accounts for that. Outlook.com has also turned off app passwords for
IMAP, so there's no way around it with a password.

What still works:

- **An app registration in an Entra directory**, made with a work or school
  account that may register apps (or a free Azure account's own directory).
  Under *Supported account types* choose one that includes **personal
  Microsoft accounts**, set **Allow public client flows** to **Yes**, add the
  delegated Microsoft Graph permission **Mail.Read**, and copy the
  **Application (client) ID**. Your live.com account then signs in to it:

  ```bash
  fathom-mail add outlook --client-id <that id>
  ```

  It opens microsoft.com/link and prints a code to enter there.
- **Without Fathom:** install Outlook on the web as an Omarchy web app and
  allow its notifications; they arrive through Omarchy's notifications. The
  deck can't show an unread count that way.

Until an account is added, the `fathom-mail` service starts, finds nothing to
watch and stops.

Fathom only asks to **read** mail. The sign-in token is kept in your GNOME
keyring, and the client ID and settings in `~/.config/fathom/mail.json`;
neither is ever in this repo. Mail is read only from Microsoft. If Microsoft
asks you to sign in again (after a password change, say), a notification
tells you to run `fathom-mail login`.

```bash
fathom-mail test        # a sample notification
fathom-mail check       # look for new mail now
fathom-mail logout      # forget the sign-in
```

## Sign-in screen

![Fathom sign-in screen](signin/preview.jpg)

A large clock, your initial in a glowing ring, and a password field. A wrong
password turns the ring and field red, shakes the field and says so. Caps Lock
gets a warning. Bottom right: the session to start, the keyboard layout (when
there is more than one), and sleep, restart and shut down.

Try it in a window without installing anything:

```bash
sddm-greeter-qt6 --test-mode --theme ~/Work/fathom/signin/fathom
```

Installing adds two things and changes nothing of Omarchy's:
`/usr/share/sddm/themes/fathom` and `/etc/sddm.conf.d/99-zz-fathom.conf`, which
sorts after Omarchy's own config so it takes effect. Delete that one file to get
Omarchy's sign-in screen back.

If the machine signs in automatically at boot (Omarchy's default with disk
encryption), the sign-in screen only appears after signing out.
`install.sh --signin` says which applies, from the `[Autologin]` user in
SDDM's configuration.

The theme has three wallpapers: **horizon** (a planet's glowing rim), **eclipse**
(a black disc with a cyan-to-violet corona) and **hexgrid** (quiet, for working).
Cycle them with `omarchy theme bg next`.

`unlock.png` is the logo on the disk-unlock screen at boot, in place of
Omarchy's. Omarchy uses it once you pick **fathom** under *Appearance › Unlock*
in its menu (or run `omarchy-plymouth-set-by-theme fathom`); that asks for your
password and rebuilds the boot image, and *Default* there puts Omarchy's back.
`preview-unlock.png` is the picture of that screen the menu shows, made with
Omarchy's `omarchy-plymouth-preview`; without it, Omarchy doesn't offer Fathom
there.

## Personalise

![Fathom's Personalise page](look/preview.jpg)

Personalise is the deck's last page: **Super+Alt+I**, Ctrl+Tab from Crumbs,
or search Start for "personalise". It changes how Fathom looks:

- **Accent:** one of eight colours from Fathom's palette, or any `#rrggbb`.
  Borders, highlights, buttons and the glow use it, in Fathom and in
  Omarchy's own panels, menus and notifications.
- **Window frame:** the focused window's border as a gradient from the
  accent to a second colour (Fathom's is cyan to violet), or the accent alone.
- **Corners:** 0 to 30 px (Fathom's is 22). Windows, Fathom's panels and
  Omarchy's menus and notifications share them.
- **Panel opacity:** 60 to 100% (Fathom's is 90%) for Fathom's panels and
  Omarchy's menus, launcher, popups, tooltips and notifications. It shows
  only while Hyprland's blur is on; with blur off, panels are solid, and the
  page says so.
- **Glow** along the top of Fathom's panels, on or off.
- **Bar:** Omarchy's bar background, glassy, solid or clear. This one, and
  the **wallpaper**, change as soon as you click.

The rest wait in a preview until **Apply**. **Fathom's look** puts the
shipped look back in the draft. Applying rebuilds the theme and refreshes
it: one `fathom-look set` took 407 ms on this laptop (2026-11-17, one run).

Your look is kept in `~/.config/fathom/look.json`. Omarchy reads the theme
from `~/.config/omarchy/themes/fathom`, which `fathom-look` builds from
Fathom's theme (`~/.local/share/fathom/theme`) with `colors.toml`,
`shell.toml` and `hyprland.lua` rewritten for your look. With Fathom's own
look the built files are the same as `theme/`'s.

```bash
fathom-look                                  # open Personalise
fathom-look state | jq .                     # the look, the bar and the wallpapers
fathom-look set accent '#ff6b81' corners 14  # change some of it and apply
fathom-look reset                            # Fathom's own look again
```

## Changing the art

The images are drawn in code, so change `art/make-art.py` rather than the
images, then:

```bash
./art/make-art.py              # everything
./art/make-art.py eclipse      # one piece: horizon, eclipse, hexgrid, preview, unlock
                               # (unlock also redraws preview-unlock.png)
fathom-look apply              # rebuild the theme and see the result
```

It needs `rsvg-convert` (librsvg) and `magick` (ImageMagick), both on Omarchy
already.

## Roadmap

| # | Part | Status |
|---|---|---|
| 1 | Skin: Omarchy theme | done |
| 2 | Sign-in screen: SDDM theme in QML | first version |
| 3 | Face login: Howdy with the IR camera (lock screen, sudo) | later |
| 4 | Mini-player: mpv + yt-dlp | first version |
| 5 | Command Deck: system, Docker, .NET, AI | first version |
| 6 | Mail notifications (Outlook.com); AI summaries later | built, parked: needs an app registration |
| 7 | Care: disk, warnings, one-click updates | first version |
| 8 | Start menu and Ask bar (asks Claude Code) | first version |
| 9 | Sentinel: firewall, sign-ins, network devices, system files, OpenSnitch; CrowdSec later | first version |
| 10 | Pulse: stack map from OpenTelemetry, and Claude Code's day | first version |
| 11 | Desk: Alt+Tab with previews, Task view, Snap layouts, Quick settings | first version |
| 12 | Personalise: accent, window frame, corners, panel opacity, glow, bar, wallpaper | first version |
| 13 | Crumbs: every browser's cookies, a map of who follows you where, blocking by policy | first version |
| 14 | Updates: `fathom-update`, semantic-version releases, a changelog | first version |
| 15 | Phone: `fathom-phone`, the laptop side of Fathom for Android (pairing, alerts, actions) | first version |

Parts that change system files or the firewall (the sign-in screen,
Sentinel, Pulse and Crumbs now; face login later) are opt-in flags on
`install.sh`. They write only files and firewall rules of their own, apart
from OpenSnitch (with `--opensnitch`) and the browser policy folders Crumbs
creates, and `uninstall.sh` removes those files and rules; what it leaves is
listed under
[Uninstall](#uninstall). Secrets such as mail tokens and API keys never go
in this repo.
