# Changelog

What changed in each Fathom release. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): a release is a
git tag `vMAJOR.MINOR.PATCH`, which `fathom-update` offers on its default
releases channel. Pre-release tags such as `v0.2.0-rc1` are never offered
there.

Each line names its commit.

## [Unreleased]

### Added

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

[Unreleased]: https://github.com/nerdcules/fathom/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/nerdcules/fathom/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nerdcules/fathom/releases/tag/v0.1.0
