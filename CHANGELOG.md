# Changelog

What changed in each Fathom release. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): a release is a
git tag `vMAJOR.MINOR.PATCH`, which `fathom-update` offers on its default
releases channel. Pre-release tags such as `v0.2.0-rc1` are never offered
there.

Each line names its commit.

## [Unreleased]

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

[Unreleased]: https://github.com/nerdcules/fathom/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nerdcules/fathom/releases/tag/v0.1.0
