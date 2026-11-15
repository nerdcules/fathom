# Fathom

A futuristic, Windows-inspired desktop layer for [Omarchy](https://omarchy.org),
built for Docker, .NET and AI work. Deep-space navy, cyan and violet, with
windows framed in a cyan-to-violet gradient.

![Fathom theme preview](theme/preview.png)

## Install

```bash
git clone <this repo> ~/Work/fathom
cd ~/Work/fathom
./install.sh            # the desktop theme, the mini-player and the Command Deck
./install.sh --signin   # adds the sign-in screen (asks for your password)
```

| Option | What it does |
|---|---|
| `--skin` | The desktop theme |
| `--player` | The mini-player, its keys and its bar widget |
| `--deck` | The Command Deck and its Care page, their keys, and Care's check every 3 hours |
| `--mail` | New-mail notifications and their background service (then add your account; see [Mail](#mail)) |
| `--signin` | The sign-in screen. Needs your password |
| `--all` | Every part |
| `--link` | Link the theme, the commands and their Hyprland files to this repo instead of copying, for working on them |
| `--no-apply` | Install the desktop theme without switching to it |

With no part named, it installs the parts that need no password: `--skin`,
`--player`, `--deck` and `--mail`.

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
                The deck itself, an Omarchy shell panel, with its Deck and
                Care pages
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
art/            make-art.py, which draws the wallpapers, preview and logo
tests/          node --test tests/ && python3 -m unittest discover -s tests
install.sh      Installer
uninstall.sh    Undo the installer
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
to change that. It needs `mpv`, `yt-dlp`, `socat`, `jq` and `wl-clipboard`,
all on Omarchy already.

Installing adds `~/.local/bin/fathom-player`, `~/.config/hypr/fathom-player.lua`,
three marked lines at the end of `~/.config/hypr/hyprland.lua` (after a
backup), and the `fathom.player` bar widget.

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
  idle. If Ollama is running, its loaded models and their VRAM.

Above the cards, a summary line puts whatever needs attention first.

The deck reads the machine only while it's open, every few seconds, and only
locally; the one network call is to Ollama on `127.0.0.1`. From a terminal:

```bash
fathom-deck status | jq .                # what the deck shows, as JSON
fathom-deck container restart <name>     # also start, stop
fathom-deck logs <name>
```

Installing adds `~/.local/bin/fathom-deck`, `~/.config/hypr/fathom-deck.lua`
(loaded from the same marked block in `hyprland.lua` as the mini-player) and
the `fathom.deck` shell plugin.

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
as Omarchy's own update check does; nothing else leaves the machine. To turn
the timer off: `systemctl --user disable --now fathom-care.timer`.

```bash
fathom-care status | jq .     # what Care shows, as JSON
fathom-care check             # check now
fathom-care clean trash npm   # free those (names from `status`)
```

## Mail

New mail in your Outlook.com inbox shows up as a notification within a
minute: the sender, the subject and the first line. Click it to open the
message in Outlook on the web. Several at once become one notification. Only
your Focused inbox notifies, like Outlook's own app; set `"focusedOnly":
false` for the account in `~/.config/fathom/mail.json` to include Other. The
deck's summary line shows how many unread emails you have.

Gmail and IMAP accounts can come later: each mail service is one module in
`mail/fathom_mail/`.

### Adding your Outlook.com account

Microsoft only lets apps read mail through an app registration of their own,
so you make one (free, about five minutes, once):

1. Sign in at [entra.microsoft.com](https://entra.microsoft.com) with your
   Microsoft account. If it says you need a directory, create the free
   default one it offers.
2. **App registrations › New registration.** Name it *Fathom Mail*. Under
   *Supported account types* pick **Personal Microsoft accounts only**. Leave
   *Redirect URI* empty and click **Register**.
3. **Authentication › Advanced settings:** set **Allow public client flows**
   to **Yes** and save.
4. **API permissions › Add a permission › Microsoft Graph › Delegated:** add
   **Mail.Read**. (User.Read is already there.)
5. From **Overview**, copy the **Application (client) ID**, then:

```bash
fathom-mail add outlook --client-id <that id>
```

It opens microsoft.com/link and prints a code to enter there. Once you've
signed in, the watcher starts.

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
| 2 | Sign-in screen: SDDM theme in QML | first version |
| 3 | Face login: Howdy with the IR camera (lock screen, sudo) | later |
| 4 | Mini-player: mpv + yt-dlp | first version |
| 5 | Command Deck: system, Docker, .NET, AI | first version |
| 6 | Mail notifications (Outlook.com); AI summaries later | **first version** |
| 7 | Care: disk, warnings, one-click updates | first version |
| 8 | Start menu and Ask bar | planned |
| 9 | Security monitor: OpenSnitch, CrowdSec, daemon, UI | planned |
| 10 | Pulse: stack map from OpenTelemetry | planned |

Parts that change system files (sign-in screen, face login, firewall) will be
opt-in flags on `install.sh`, back up what they replace, and be undone by
`uninstall.sh`. Secrets such as mail tokens and API keys never go in this repo.
