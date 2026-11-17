#!/usr/bin/env python3
"""Cuts the promo from its parts:

  assemble.py <work dir> <out.mp4> [--no-voice]

The work dir holds stills/ (Scene.qml's page renders, Card.qml's cards),
takes/ (take.sh's desk.mp4 and look.mp4) and vo/ (voice.py's lines and
lengths.json). Each shot becomes a 1920x1080 clip; the clips crossfade, the
voice lines start 0.4 s into their shots, captions are burned in, and a
quiet synthesized pad sits under the voice, ducking while it speaks.
With --no-voice the captions carry the words alone, with no sound at all.
"""

import json
import os
import subprocess
import sys

W, H, FPS = 1920, 1080, 30
FADE = 0.4          # crossfade between shots
LEAD = 0.4          # voice starts this far into its shot
TAIL = 0.9          # and the shot runs this long after it
FRAME_W = 1620      # a 3:2 screen, 1080 high, centred
FONT = "JetBrainsMono Nerd Font"

# (kind, source, voice line, badge, key, live start, shortest length)
# kind: card | still | live. Live shots take a stretch of a take (times in
# take.sh); a shot runs at least its length, or its voice line plus pauses.
SHOTS = [
    ("card", "card-title.png", 1, None, None, None, None),
    ("live", "desk.mp4", 2, None, None, 1.5, None),
    ("still", "start.png", 3, "Demo data", "Tap Super", None, None),
    ("live", "desk.mp4", 4, None, "Alt+Tab · Super+Tab · Super+Z · Super+Alt+A", 7.2, 14.0),
    ("still", "deck.png", 5, "Demo data", "Super+Alt+D", None, None),
    ("still", "care.png", 6, "Demo data", "Super+Alt+C", None, None),
    ("still", "sentinel.png", 7, "Demo data", "Super+Alt+X", None, None),
    ("still", "pulse.png", 8, "Demo data", "Super+Alt+P", None, None),
    ("still", "crumbs.png", 9, "Demo data", "Super+Alt+O", None, None),
    ("live", "look.mp4", 10, None, "Super+Alt+I", 2.5, 11.0),
    ("card", "card-end.png", 11, None, None, None, None),
]


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def esc(text):
    return text.replace("\\", "\\\\").replace(":", "\\:").replace("'", "’").replace("%", "\\%")


def framed(inp, dur, zoom, badge, key):
    """Filter for a 3:2 picture centred on the blurred wallpaper."""
    frames = int(round(dur * FPS))
    fg = f"[{inp}]scale={FRAME_W}:{H}:flags=lanczos,setsar=1"
    if zoom:
        # A slow push-in, 1.000 -> 1.035 over the shot.
        fg += (f",zoompan=z='1+0.035*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
               f":d={frames}:s={FRAME_W}x{H}:fps={FPS}")
    fg += "[fg]"
    return fg + f";[bg][fg]overlay=(W-w)/2:0" + labels(badge, key, (W - FRAME_W) // 2)


def labels(badge, key, inset):
    """The "Demo data" badge top right and the shot's keys top left, inside
    a picture inset this far from the frame's sides."""
    out = ""
    if badge:
        out += (f",drawtext=font='{FONT}':text='{esc(badge)}':fontsize=24:fontcolor=0xe6f0ff"
                f":box=1:boxcolor=0x9d8cff@0.6:boxborderw=10:x=W-({inset}+tw+30):y=26")
    if key:
        out += (f",drawtext=font='{FONT}':text='{esc(key)}':fontsize=24:fontcolor=0xe6f0ff"
                f":box=1:boxcolor=0x0a1020@0.8:boxborderw=10:x={inset + 30}:y=26")
    return out


def clip(work, shot, dur, dest, bg):
    kind, src, _, badge, key, start, _ = shot
    if kind == "card":
        path = os.path.join(work, "stills", src)
        frames = int(round(dur * FPS))
        vf = (f"scale={W}:{H},zoompan=z='1+0.03*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
              f":d={frames}:s={W}x{H}:fps={FPS},format=yuv420p")
        run(["ffmpeg", "-y", "-loop", "1", "-i", path, "-t", f"{dur:.3f}", "-vf", vf,
             "-r", str(FPS), "-c:v", "libx264", "-crf", "16", "-preset", "medium", dest])
        return
    if kind == "still":
        # Scene.qml renders the pages full frame: a slow push-in and labels.
        frames = int(round(dur * FPS))
        vf = (f"scale={W}:{H},zoompan=z='1+0.035*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
              f":d={frames}:s={W}x{H}:fps={FPS}" + labels(badge, key, 0) + ",format=yuv420p")
        run(["ffmpeg", "-y", "-loop", "1", "-i", os.path.join(work, "stills", src), "-t", f"{dur:.3f}",
             "-vf", vf, "-r", str(FPS), "-c:v", "libx264", "-crf", "16", "-preset", "medium", dest])
        return
    inputs = ["-ss", f"{start:.3f}", "-i", os.path.join(work, "takes", src)]
    fc = framed("0:v", dur, False, badge, key).replace("[bg]", "[1:v]")
    fc += ",format=yuv420p,fps=30[v]"
    run(["ffmpeg", "-y", *inputs, "-loop", "1", "-i", bg, "-t", f"{dur:.3f}",
         "-filter_complex", fc, "-map", "[v]", "-r", str(FPS), "-c:v", "libx264", "-crf", "16",
         "-preset", "medium", dest])


def ass_time(t):
    h, rem = divmod(t, 3600)
    m, s = divmod(rem, 60)
    return f"{int(h)}:{int(m):02d}:{s:05.2f}"


def captions(lines, starts, lengths, path):
    head = (
        "[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\n\n"
        "[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, "
        "BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, "
        "Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
        f"Style: Cap,{FONT},34,&H00FFF0E6,&H00FFFFFF,&H00201004,&HB0100A04,0,0,0,0,100,100,0,0,3,"
        "14,0,2,260,260,46,1\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, "
        "MarginV, Effect, Text\n")
    with open(path, "w") as f:
        f.write(head)
        for text, t0, n in zip(lines, starts, lengths):
            f.write(f"Dialogue: 0,{ass_time(t0)},{ass_time(t0 + n + 0.3)},Cap,,0,0,0,,{text}\n")


def main(work, out, voiced=True):
    with open(os.path.join(work, "vo", "lengths.json")) as f:
        lengths = json.load(f)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    lines = caption_lines()
    tmp = os.path.join(work, "cut")
    os.makedirs(tmp, exist_ok=True)

    # The wallpaper behind 3:2 pictures, blurred and dimmed.
    bg = os.path.join(tmp, "bg.png")
    here = os.path.dirname(os.path.abspath(__file__))
    run(["magick", os.path.join(here, "..", "theme", "backgrounds", "1-horizon.webp"),
         "-resize", f"{W}x{H}^", "-gravity", "center", "-extent", f"{W}x{H}",
         "-blur", "0x18", "-modulate", "60", bg])

    durs = [max(lengths[s[2] - 1] + LEAD + TAIL, s[6] or 0) for s in SHOTS]
    clips = []
    for i, (shot, dur) in enumerate(zip(SHOTS, durs)):
        dest = os.path.join(tmp, f"shot{i + 1:02d}.mp4")
        clip(work, shot, dur, dest, bg)
        clips.append(dest)

    # Shot i starts where the crossfades put it.
    starts, t = [], 0.0
    for d in durs:
        starts.append(t)
        t += d - FADE
    total = starts[-1] + durs[-1]

    # Crossfade the clips in a chain.
    inputs, fc, last = [], [], "0:v"
    for c in clips:
        inputs += ["-i", c]
    for i in range(1, len(clips)):
        label = f"x{i}"
        fc.append(f"[{last}][{i}:v]xfade=transition=fade:duration={FADE}:offset={starts[i]:.3f}[{label}]")
        last = label
    ass = os.path.join(tmp, "captions.ass")
    voice_at = [s + LEAD for s in starts]
    captions(lines, voice_at, lengths, ass)
    fc.append(f"[{last}]ass={ass},fade=t=in:st=0:d=0.6,fade=t=out:st={total - 1.0:.3f}:d=1.0[v]")
    video = os.path.join(tmp, "video.mp4")
    run(["ffmpeg", "-y", *inputs, "-filter_complex", ";".join(fc), "-map", "[v]",
         "-c:v", "libx264", "-crf", "18", "-preset", "slow", "-pix_fmt", "yuv420p", video])

    if not voiced:
        run(["ffmpeg", "-y", "-i", video, "-map", "0:v", "-c:v", "copy", "-an", "-movflags", "+faststart", out])
        print(f"{out}: {total:.2f} s, {len(SHOTS)} shots, no sound")
        return

    # Voice on the timeline.
    vo_in, vo_fc = [], []
    for i, at in enumerate(voice_at):
        vo_in += ["-i", os.path.join(work, "vo", f"vo{i + 1:02d}.wav")]
        ms = int(round(at * 1000))
        vo_fc.append(f"[{i}:a]aresample=48000,adelay={ms}|{ms},apad[a{i}]")
    vo_fc.append("".join(f"[a{i}]" for i in range(len(voice_at))) +
                 f"amix=inputs={len(voice_at)}:normalize=0,atrim=0:{total:.3f}[voice]")
    voice = os.path.join(tmp, "voice.wav")
    run(["ffmpeg", "-y", *vo_in, "-filter_complex", ";".join(vo_fc), "-map", "[voice]",
         "-ac", "1", "-ar", "48000", voice])

    # A soft pad: A, E, A, C# with a slow swell, low-passed.
    pad = ("0.08*sin(2*PI*110*t)+0.06*sin(2*PI*164.81*t)+0.05*sin(2*PI*220*t)+0.035*sin(2*PI*277.18*t)"
           "+0.02*sin(2*PI*329.63*t)")
    swell = "(0.75+0.25*sin(2*PI*t/9))"
    music = os.path.join(tmp, "music.wav")
    run(["ffmpeg", "-y", "-f", "lavfi", "-i", f"aevalsrc='({pad})*{swell}':s=48000:d={total:.3f}",
         "-af", f"lowpass=f=1800,afade=t=in:d=2,afade=t=out:st={total - 3:.3f}:d=3", "-ac", "1", music])

    mix = os.path.join(tmp, "mix.wav")
    run(["ffmpeg", "-y", "-i", voice, "-i", music, "-filter_complex",
         "[1:a]volume=0.45[m];[0:a]asplit=2[v1][v2];"
         "[m][v2]sidechaincompress=threshold=0.03:ratio=6:attack=20:release=400[duck];"
         "[v1][duck]amix=inputs=2:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11[out]",
         "-map", "[out]", "-ar", "48000", mix])

    run(["ffmpeg", "-y", "-i", video, "-i", mix, "-map", "0:v", "-map", "1:a", "-c:v", "copy",
         "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", out])
    print(f"{out}: {total:.2f} s, {len(SHOTS)} shots")
    for i, (s, d) in enumerate(zip(starts, durs), 1):
        print(f"  shot {i:2d} at {s:6.2f} s, {d:5.2f} s, {SHOTS[i - 1][1]}")


def caption_lines():
    # The captions say what the voice says, as written (voice.py spells some
    # words for the voice).
    return [
        "This is Fathom: a futuristic, Windows-inspired desktop layer for Omarchy,\\Nbuilt for Docker, .NET and AI work.",
        "Deep-space navy, cyan and violet, with every window framed in a gradient.",
        "Tap Super for Start: find an app, open a recent project,\\Nor ask Claude Code, right from the search box.",
        "Alt+Tab shows window previews. Task view lays out every window and workspace.\\NSnap layouts tile a window in one move, and Quick settings is a key away.",
        "The Command Deck shows your machine at a glance: the system,\\Nyour containers, .NET apps, and the AI agents at work.",
        "Care watches the disk, warnings and updates, and clears out caches.",
        "Sentinel watches firewall blocks, sign-ins, USB drives,\\Nnew devices on your network, and system files.",
        "Pulse is a small OpenTelemetry collector that maps what calls what in your stack,\\Nnext to your day with Claude Code.",
        "Crumbs finds the cookies in Edge, Chrome, Chromium, Brave and Firefox, shows which sites\\Nled you to which trackers, and blocks them by browser policy.",
        "And Personalise changes the accent, the window frame, the corners and the glass,\\Nacross the desktop at once.",
        "Fathom is free and open source. The idea is nerdcules’; it was written by Claude, in Claude Code.",
    ]


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--no-voice"]
    if len(args) != 2:
        sys.exit(__doc__.strip())
    main(args[0], args[1], voiced="--no-voice" not in sys.argv)
