# Fathom

A futuristic, Windows-inspired desktop layer for [Omarchy](https://omarchy.org),
built for Docker, .NET and AI work. Deep-space navy, cyan and violet, with
windows framed in a cyan-to-violet gradient.

![Fathom theme preview](theme/preview.png)

## Install

```bash
git clone <this repo> ~/Work/fathom
cd ~/Work/fathom
./install.sh            # installs and applies the desktop theme
./install.sh --signin   # adds the sign-in screen (asks for your password)
```

| Option | What it does |
|---|---|
| `--skin` | The desktop theme (what you get when no part is named) |
| `--signin` | The sign-in screen. Needs your password |
| `--all` | Every part |
| `--link` | Symlink the desktop theme to this repo instead of copying, for working on it |
| `--no-apply` | Install the desktop theme without switching to it |

`./uninstall.sh` switches back to the theme that was on before, removes
what the installer added, and puts Omarchy's sign-in screen back. It leaves
alone any `fathom` theme it did not make.

## What's here

```
theme/          The Omarchy desktop theme: colours, wallpapers, icons,
                preview, boot unlock logo
signin/fathom/  The sign-in screen, an SDDM theme in QML
signin/install-root.sh
                The only part that runs as root: copies the sign-in theme
                and selects it
art/            make-art.py, which draws the wallpapers, preview and logo
install.sh      Installer
uninstall.sh    Undo the installer
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
| 1 | Skin: Omarchy theme | done |
| 2 | Sign-in screen: SDDM theme in QML | **first version** |
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
