# Fathom

A futuristic, Windows-inspired desktop layer for [Omarchy](https://omarchy.org),
built for Docker, .NET and AI work. Deep-space navy, cyan and violet, with
windows framed in a cyan-to-violet gradient.

![Fathom theme preview](theme/preview.png)

## Install

```bash
git clone <this repo> ~/Work/fathom
cd ~/Work/fathom
./install.sh            # installs and applies the theme
```

| Option | What it does |
|---|---|
| `--skin` | Install the theme (the default while it is the only part) |
| `--link` | Symlink the theme to this repo instead of copying, for working on it |
| `--no-apply` | Install without switching to it |

`./uninstall.sh` switches back to the theme that was on before and removes
what the installer added. It leaves alone any `fathom` theme it did not make.

## What's here

```
theme/          The Omarchy theme: colours, wallpapers, icons, preview,
                boot unlock logo
art/            make-art.py, which draws the wallpapers, preview and logo
install.sh      Installer
uninstall.sh    Undo the installer
```

The theme has three wallpapers: **horizon** (a planet's glowing rim), **eclipse**
(a black disc with a cyan-to-violet corona) and **hexgrid** (quiet, for working).
Cycle them with `omarchy theme bg next`.

`unlock.png` is the logo on the disk-unlock screen at boot. Omarchy only uses it
if you pick Fathom under *Appearance › Unlock*, which needs your password.

## Changing the art

The images are drawn in code, so change `art/make-art.py` rather than the
images, then:

```bash
./art/make-art.py              # everything
./art/make-art.py eclipse      # one piece: horizon, eclipse, hexgrid, preview, unlock
omarchy theme set fathom       # see the result
```

It needs `rsvg-convert` (librsvg) and `magick` (ImageMagick), both on Omarchy
already.

## Roadmap

| # | Part | Status |
|---|---|---|
| 1 | Skin: Omarchy theme | **in progress** |
| 2 | Sign-in screen: SDDM theme in QML | planned |
| 3 | Face login: Howdy with the IR camera (lock screen, sudo) | planned |
| 4 | Mini-player: mpv + yt-dlp | planned |
| 5 | Command Deck widgets: Docker, .NET, AI, disk | planned |
| 6 | Notifications: mail with AI summaries | planned |
| 7 | Care: disk, warnings, one-click updates | planned |
| 8 | Start menu and Ask bar | planned |
| 9 | Security monitor: OpenSnitch, CrowdSec, daemon, UI | planned |
| 10 | Pulse: stack map from OpenTelemetry | planned |

Parts that change system files (sign-in screen, face login, firewall) will be
opt-in flags on `install.sh`, back up what they replace, and be undone by
`uninstall.sh`. Secrets such as mail tokens and API keys never go in this repo.
