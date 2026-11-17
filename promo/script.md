# Fathom promo: shot list and voiceover

About 90 s, 1920×1080, 30 fps. Voice: Kokoro `af_heart`. Live shots are
screen recordings of this laptop (2304×1536 logical, 3:2) on a staged
workspace; "demo" shots are the real pages rendered by `Scene.qml` from
`demo-data.py`'s made-up data, and carry a "Demo data" badge. Every claim
is listed with where it comes from.

| # | Shot | Voiceover | Source |
|---|---|---|---|
| 1 | Title card on the Horizon wallpaper | This is Fathom: a futuristic, Windows-inspired desktop layer for Omarchy, built for Docker, dot NET and AI work. | README intro |
| 2 | Live: the desktop, windows in their frames | Deep-space navy, cyan and violet, with every window framed in a gradient. | README intro; theme/hyprland.lua |
| 3 | Demo: Start | Tap Super for Start: find an app, open a recent project, or ask Claude Code from the search box. | README, Start menu |
| 4 | Live: Alt+Tab, Task view, Snap layouts, Quick settings | Alt Tab shows window previews. Task view lays out every window and workspace. Snap layouts tile a window in one move, and Quick settings is a key away. | README, Desk |
| 5 | Demo: Command Deck | The Command Deck shows your machine at a glance: the system, your containers, dot NET apps, and the AI agents at work. | README, Command Deck |
| 6 | Demo: Care | Care watches the disk, warnings and updates, and clears out caches. | README, Care |
| 7 | Demo: Sentinel | Sentinel watches firewall blocks, sign-ins, USB drives, new devices on your network, and system files. | install.sh --help, --sentinel |
| 8 | Demo: Pulse | Pulse is a small OpenTelemetry collector that maps what calls what in your stack, next to your day with Claude Code. | README, Pulse |
| 9 | Demo: Crumbs | Crumbs finds the cookies in Edge, Chrome, Chromium, Brave and Firefox, shows which sites led you to which trackers, and blocks them by browser policy. | README, Crumbs; fathom-crumbs CHROMIUM_BROWSERS, FIREFOX_BROWSERS; blocking is Chromium-family only |
| 10 | Live: Personalise, the accent and corners changing | And Personalise changes the accent, the window frame, the corners and the glass, across the desktop at once. | README, Personalise |
| 11 | End card | Fathom is free and open source. The idea is nerdcules'; it was written by Claude, in Claude Code. | LICENSE (MIT); `git log` at 3d2e74a: 31 of 31 commits carry `Co-Authored-By: Claude` |

End card text: Fathom · github.com/nerdcules/fathom · MIT licence ·
Idea: nerdcules · Written by Claude, in Claude Code · 31 of 31 commits
co-authored by Claude (3d2e74a, 17 Nov 2026) · Tests at 3d2e74a: 129 Python
and 58 Node, all passing.
