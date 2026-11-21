# Changelog

What changed in each Fathom release. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): a release is a
git tag `vMAJOR.MINOR.PATCH`, which `fathom-update` offers on its default
releases channel. Pre-release tags such as `v0.2.0-rc1` are never offered
there; the prereleases channel offers them, and the release once it's
tagged.

Each line names its commit.

## [Unreleased]

### Added

- The bar's cluster (#14): Omarchy's Bluetooth, network, volume and
  battery widgets become one button, with their glyphs, that opens Quick
  settings (right-click: its Wi-Fi list; middle-click: mute; scroll:
  volume). `install.sh --desk` puts it where the last of them was and keeps
  their places; `uninstall.sh` puts them back (fb23edb, 2e6cc26, 137102b).
- Fathom's own dropdowns for the bar's items (#14), in Quick settings'
  look, starting with Display: brightness, text size, scale presets
  (labelled as the screen gets them) and, with more than one display, a
  row for each. Each is a clone of Omarchy's item, so `install.sh --desk`
  puts it in that item's place with its settings, Omarchy's key
  (Super+Ctrl+D) and IPC (`omarchy-shell omarchy.monitor state`) reach it,
  and `uninstall.sh` puts Omarchy's back. Built from a shared kit
  (`kit/`) whose factory draws a dropdown from a list of sections.
  `bar/items.json` lists every Omarchy bar item with its Fathom dropdown
  or plan, and a test fails when Omarchy has one it doesn't name; the
  install names the bar items still without one.
- The clock's Fathom dropdown: Omarchy's label (formats, right-click to
  change, middle-click for the time zone) with Fathom's calendar: the
  month with ISO week numbers and today lit, the year so far, and
  Omarchy's life bar; its keys and settings are Omarchy's. The kit's
  factory gained a meter and text fields, and a card can take keys of its
  own first.
- The weather's Fathom dropdown: Omarchy's icon, sources (wttr.in,
  open-meteo, Omarchy's place lookup) and settings, with Fathom's
  dropdown: the temperature, feels-like, wind and humidity, the place
  (search for another, or go back to where you are), and the coming days.
  Unlike Omarchy's, a place being saved stops waiting when open-meteo
  keeps failing, instead of saying "Loading…" for good. The factory gained
  facts, a strip of tiles and a search field.
- A check that Fathom's dropdowns keep up with Omarchy: `bar/items.json`
  records the Omarchy files each copies behaviour from, with a
  fingerprint, and `tests/test_bar.py` fails when Omarchy changes one.
- One look everywhere: the bar's dropdowns size for the screen by the
  rule the Command Deck and the desk use, so their text, sliders and
  buttons match Quick settings'.
- Quick settings by keyboard (#15): Tab or the arrows (or j and k) move
  between its tiles, sliders, buttons and list rows, Space or Return
  toggles or picks, Right (or l) opens a tile's list and Left (or h) comes
  back to that tile, and a line at the foot says so. Before, only Esc did
  anything.
- Quick settings lists Wi-Fi networks and Bluetooth devices itself, behind
  the arrows on their tiles: join, leave, a password field, pair, connect
  (b52638d). `fathom-desk quick wifi|bluetooth` opens it on a list.

### Changed

- One kit instead of three copies (#22): the Command Deck, the desk and
  the bar's dropdowns draw with one skin, one button (`Pill`), one panel
  (`Glass`, now also the Start menu's and the deck's cards), one label,
  tooltip and status dot, from `kit/`, which `install.sh` copies into
  each plugin. The copies had drifted (only the deck's skin had number
  formatting and dialogs; only the desk's and the dropdowns' had the scrim
  and motion timing). `tests/test_one_look.py` now fails if a plugin
  grows its own copy, uses something the skin lacks, or takes the theme
  or its size differently. Buttons in Quick settings, Snap layouts and the
  dropdowns are now the deck's: padding of 20 units (was 22, at Fathom's
  size for the screen), and a lit (primary) one has a semibold word.
- One set of state strengths everywhere (#18), Omarchy's own: hover
  tints the accent at 0.12 and pressed at 0.22; selected, on, chosen and a
  list's cursor fill with it at 0.36 with a 0.8 edge. Fathom's buttons,
  Quick settings' tiles and lists, the dropdowns' rows, the deck's lists and
  Start's pinned apps drew these four ways (a picked button was 0.22 with a
  full edge, a list's cursor 0.16 with none; hover was grey on the tiles).
- Idle buttons and text fields have an edge you can see (#21): the
  foreground at 0.4, 3.47:1 against the panel, over WCAG's 3:1 for a
  control's edge. The theme's idle edge for Omarchy's own controls goes
  back to Omarchy's default, the same 0.4 (it was 0.18, 1.62:1).
- A focus ring (#16): where the keyboard is shows as 2 px of the
  foreground just outside the button, row, tile, swatch or slider knob,
  apart from the selected look; before, a picked choice on Personalise
  didn't change when it took focus. Omarchy's own controls under the theme
  show focus as a 2 px foreground edge (was the accent at 0.45, as hover).
- Status marks tell their states apart by shape as well as colour (#17):
  ok is a filled disc, a warning a ring, a problem a diamond, idle a hollow
  disc. Green and red are 1.55:1 apart in lightness and green and amber
  1.01:1, so by colour alone they were one dot without colour vision.
- The corners inside Fathom's panels follow Personalise's corners (#19):
  a tile is 14 units at Fathom's 22, square at 0 and 19 at 30, and so on
  for rows, cards and tooltips. They stayed fixed while the panels around
  them changed. Buttons, sliders and status marks stay round.
- A named type scale (#20): every text size comes from ten named sizes
  (caption 11, detail 12, body 13, label 14, title 15, large 17, heading
  18, greeting 26, display 30, clock 84, times Fathom's size for the
  screen). Five one-off sizes moved onto the nearest: Quick settings'
  battery glyph 16 to 17, its tiles' glyphs 19 to 18, Pulse's figures and
  Task view's heading 20 to 18, the weather's day glyphs 22 to 18.
- The theme brings the bar's dropdowns closer to Quick settings (#14):
  more padding and row room, taller buttons, larger titles, and the
  selected state filled like Quick settings' tiles (41e603a).

### Fixed

- `fathom-update` didn't reinstall the desk when only the bar's
  dropdowns (`bar/`) changed, so they stayed at the old version; it does
  now, and reinstalls the deck and the desk when the kit changes.
- `fathom-desk --help` no longer prints `set -euo pipefail` (b52638d).
- Super+Ctrl+A, B, N and P did nothing once the cluster had taken
  Omarchy's audio, Bluetooth, network and power widgets off the bar; they
  open Quick settings now (B and N on their lists).

## [0.4.0] - 2026-11-20

The Ward offer, a prereleases channel, PCs on the deck, and Start's power
menu clicking only what's on top.

### Added

- An offer to set up Ward, which checks this machine against the published
  CVEs daily: `./install.sh --sentinel` asks once at a terminal, Care's
  Warnings lists it (Set up, Not now), and Sentinel's page has a Set up
  button; once it's installed, Sentinel shows what its last check found and
  Care warns about CVEs it rated "now". `fathom-care ward status|setup|install|dismiss`
  (282060c).
- `fathom-update channel prereleases`: the newest tag, pre-releases such
  as `v0.4.0-rc.1` included, and the release once it's tagged; the
  releases channel still never offers a pre-release (6b362da).
- PCs on the deck: a paired PC (Fathom for Windows) sends its own figures
  (`POST /v1/device/status`), `fathom-phone pcs` lists them, the deck shows
  a PCs card (a disk with room in green, not the accent), and a PC's
  warnings become alerts (f047529, 3d70d60).
- `fathom-phone` pairs PCs too: pairing takes a `kind` (`phone`, the
  default, or `pc`), `fathom-phone devices` and `status` show it, and
  `fathom-phone pair` prints its link as text to paste into the PC app
  (173c08e).

### Changed

- Ward's exploited count leaves out CVEs Ward settled as "later" (in a
  Docker image nothing runs, say), and `install.sh` checks for Ward through
  `FATHOM_WARD` like `fathom-care` (cea554d).
- The test alert says it reached "this device", and an item marked done in
  Sankofa from a paired device names that device instead of "the phone"
  (173c08e).

### Fixed

- Start: clicking Lock, Sign out or Restart in the power menu no longer
  also opens the Recent project under it (#13, 97c3478); no TapHandler is
  left in the deck, and a test keeps it that way (eb8d811).
- Start and Confirm: the row under the power menu, the About card or a
  Confirm dialog no longer lights up as the pointer passes over it
  (dfb166e).
- `tests/vm/check.sh` answers Ward's question when `--sentinel` asks it,
  instead of waiting out the step's 5 minutes (798ad3b).

## [0.3.0] - 2026-11-20

Blueprint as the screensaver, Super+Tab from the keyboard, the screensaver
on Personalise, IP addresses on the panel, and Care up to date after
updates.

### Added

- Screensaver: Blueprint, software patterns and architectures drawn as
  blueprints (65 sheets), comes into Fathom (`screensaver/blueprint`).
  `./install.sh --screensaver` builds it, installs `fathom-screensaver`,
  and clones Omarchy's idle service as `fathom.idle` with only its
  screensaver line changed; Personalise and `fathom-look screensaver shows
  blueprint` pick it. An idle service of your own is left alone (020e591).
- Quick settings and the deck's System card list this machine's IP
  addresses: each interface that is up (Wi-Fi, Ethernet, Tailscale, VPN),
  its IPv4 and IPv6 ones, each with a copy button. From `ip -j addr`, in
  `fathom-desk settings` and `fathom-deck status` as `addresses` (2e14ce5).
- Task view: hold Super and press Tab again to step through the
  workspaces, and let go of Super to go there (Hyprland submap
  `fathom-tasks`); with Task view open, Tab and Shift+Tab look at the other
  workspaces and Enter goes to an empty one. The workspace looked at is lit
  in the accent (82bbfb4).
- Personalise: a Screensaver card, and `fathom-look screensaver`: off or
  when it starts, when the screen locks (or never), what it shows (Omarchy's
  logo, Fathom's name, a picture or your own text) and a preview. They are
  Omarchy's idle settings, written through `omarchy-shell-config` (8a5c41f).
- `tests/vm`: the VM checks run in WSL2 on Windows 11, with
  `FATHOM_VM_DISPLAY=vnc` (no 3D), and `run.sh` types the VM disk's
  passphrase from a file there (`qmp.py`) (2113525).

### Fixed

- `./install.sh --screensaver` could switch your own idle service off
  when it ran just after `--skin` switched the theme: it asked the running
  shell, which didn't list it. It reads `shell.json` and the plugins'
  manifests now (c913a63).
- Care: after updates, its list and count of updates stayed as they were
  until the next 3-hourly check. **Update everything** checks again when
  Omarchy's update ends, and a list from before pacman's last change to
  what's installed (by Care, Omarchy's menu, pacman or yay) isn't shown:
  Care checks again, once pacman is done and once for each change. A check
  now dates itself from when it started, not when it ended (812c4d1).
- Start: the power menu opened at the top of the Start menu, not above its
  button (its place was worked out once, before the layout, by a
  `mapToItem()` QML doesn't follow). It is placed as it opens now, takes the
  arrow keys, Enter and Esc, and Sign out, Restart and Shut down ask in the
  menu itself instead of in the middle of the screen (1e73e9c).
- Theme: Omarchy's bar panels (Wi-Fi, Bluetooth, sound and the rest) didn't
  look like Fathom: their switches, picked buttons and lists were grey, and
  at 90% opacity with no blur behind them the text under them read
  through. Their controls take the accent now, and the panels and tooltips
  are solid; `fathom-look`'s opacity leaves them alone (df422fa).
- `tests/vm/run.sh` stopped at once, saying nothing, when the VM folder had
  no installer image; it needs one only for `run.sh install` now (2113525).

## [0.2.0] - 2026-11-18

The laptop side of Fathom for Android, and Fathom's version on screen.

### Added

- `fathom-phone` (`./install.sh --phone`): the laptop side of Fathom for
  Android. An HTTPS service on port 4920 with a self-signed certificate the
  phone pins, pairing by QR code (a one-time secret, 2 minutes, 5 tries), a
  token per phone kept only as its SHA-256, the deck's parts for the phone
  to read, `devices` and `unpair`; a firewall rule for the home network and
  Tailscale (e5daf83).
- Alerts for the phone: what needs a look (a failed service, disk filling,
  a restart to finish an update, a container in trouble, Sentinel's
  warnings from the last day, errors in Pulse, Claude Code waiting, a Fathom
  update), each with an id that stays the same while it's true. A phone can
  take only the actions an alert offers (trust a device, restart a failed
  service, block an address), with the arguments from the laptop's own copy
  of the alert; those needing root ask for the password on the laptop.
  `fathom-phone alerts` and `test-alert` (00e462b).
- Sankofa for the phone: each repo's open items, leases held and last note;
  an item waiting on you is an alert, with Done (9b4d00c).
- A phone can unpair itself, so forgetting the laptop in the app stops its
  token working here; every pairing attempt is logged (310a213).
- Phone health, when the phone's owner turns it on: battery charge,
  charging, battery temperature, thermal status, storage and each app's
  foreground and background time, kept 35 days, readable by you alone and
  deleted on unpair. Rules compare the last day with the six before it
  (faster battery drain, naming an app behind it; heat slowdowns; storage
  90% full), and their findings are alerts. `fathom-phone health [week]`
  (dd69b57).
- Ask Claude on the laptop: the phone asks about a health finding and
  Claude Code answers here, from a question `fathom-phone` writes out of its
  own data, with no tools, MCP servers, settings or hooks, and nothing
  saved; one question at a time, 20 a day per phone (b8cd76d). The question
  is targeted: only the finding's evidence, the usual causes and a fixed
  answer shape; `phone/tools/ask-compare` compares styles and models
  (7e680b0).
- Fathom's version, as the release, build number (commits since that
  release) and commit, e.g. "v0.2.0 · build 0 · 1a2b3c4": in each deck
  page's footer, Start, the About card, the bar pill's tooltip, Quick
  settings and the sign-in screen (not Alt+Tab, Task view, Snap layouts,
  the mini-player or mail). `install.sh` stamps it into what it installs
  and its record; `fathom-update version` prints it (de83adc, eb5fdbb,
  cbea201).

## [0.1.0] - 2026-11-17

The first release: everything Fathom had on 17 November 2026.

### Added

- `fathom-update`: check for a newer Fathom, install it and go back
  (`rollback`); follows releases by default, or every commit on `main`;
  Care's Updates card shows a ready update when `fathom-update auto on`
  (332a7c4).
- `tests/vm`: the install, upgrade, uninstall and firewall checks in a
  disposable Omarchy VM (ffbe129).
- Crumbs: every browser's cookies, the sites that led to trackers, and
  blocking them by browser policy (3d2e74a).
- Personalise: the accent, window frame, corners, panel opacity, glow, bar
  and wallpaper, from the deck (6a7cbe7).
- Start: About Fathom (c204d2a).
- The theme: a glassy bar and popups (ff916d9), one panel style everywhere
  (8966db5), 22 px corners (4c58316), the boot unlock logo (8c748f6).
- The desk: Alt+Tab, Task view, Snap layouts and Quick settings (d046d42).
- The deck's pill in the bar (e69a3e5); Claude Code's own busy/idle on the
  AI card (e72dcc9).
- Pulse: an OpenTelemetry stack map (b84a387) and Agents today (432df91).
- Sentinel (8ba98cb), the Start menu (42c8440), Fathom Mail (0e218f8),
  Care (816db32), the Command Deck (2dbc73f), the mini-player (db329a2),
  the sign-in screen (52893d2), and the theme and installer (6e216ad).

### Changed

- install.sh stages plugins and the theme and keeps what you have until the
  replacement works; a failed part prints what finished and how to carry
  on (45e7e61).
- The sign-in step says the machine signs in automatically only where
  SDDM's `[Autologin]` says so (0877ec1).
- Deck and Start are solid, not see-through, when Hyprland's blur is off
  (fe50d8e, 7ad3887).

### Fixed

- uninstall.sh could freeze Hyprland: it deleted the files Fathom's block in
  `hyprland.lua` loads before taking the block out (6b4f7d0).
- Sentinel's firewall buttons and uninstall could remove a ufw rule of yours
  identical to Fathom's; they now remove only Fathom's own (fbf3f42).
- Pulse's firewall rule had the same fault: uninstall now removes it by its
  comment, and install no longer takes over a matching rule of yours
  (fbf3f42).
- Sentinel didn't show IPv6 blocks (it read only `user.rules`), and a
  firewall button that was refused failed silently; it now reads both
  files and sends a notification (fbf3f42).
- The README now names every root step, what Mail does with no account, and
  what uninstall deletes (658b7d0).
- Sentinel: a TV answering discovery isn't a port scan (d4e7200); the daily
  file check's cache is held to 1 GiB (c4c85b8).
- Deck and Care: one tool's odd answer no longer blanks a page (5195495);
  the disks df could read still show when one mount can't be (2bffc44).
- Care's own description said its check runs hourly; it runs every 3 hours
  (332a7c4).

[Unreleased]: https://github.com/nerdcules/fathom/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/nerdcules/fathom/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/nerdcules/fathom/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/nerdcules/fathom/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nerdcules/fathom/releases/tag/v0.1.0
