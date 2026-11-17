"""Voices the promo's lines with Kokoro af_heart, one WAV per shot.

  python voice.py <kokoro dir> <out dir>
The kokoro dir holds kokoro-v1.0.onnx and voices-v1.0.bin (kokoro-onnx's
model-files-v1.0 release). Prints each line's length in seconds.
"""
import json
import os
import sys

import soundfile as sf
from kokoro_onnx import Kokoro

# Spelled for the voice; script.md has the words as written.
LINES = [
    "This is Fathom: a futuristic, Windows-inspired desktop layer for Omarchy, built for Docker, dot NET, and AI work.",
    "Deep-space navy, cyan and violet, with every window framed in a gradient.",
    "Tap Super for Start: find an app, open a recent project, or ask Claude Code, right from the search box.",
    "Alt Tab shows window previews. Task view lays out every window and workspace. Snap layouts tile a window in one move, and Quick settings is a key away.",
    "The Command Deck shows your machine at a glance: the system, your containers, dot NET apps, and the AI agents at work.",
    "Care watches the disk, warnings and updates, and clears out caches.",
    "Sentinel watches firewall blocks, sign-ins, USB drives, new devices on your network, and system files.",
    "Pulse is a small OpenTelemetry collector that maps what calls what in your stack, next to your day with Claude Code.",
    "Crumbs finds the cookies in Edge, Chrome, Chromium, Brave and Firefox, shows which sites led you to which trackers, and blocks them by browser policy.",
    "And Personalise changes the accent, the window frame, the corners and the glass, across the desktop at once.",
    "Fathom is free and open source. The idea is nerd-cules's. It was written by Claude, in Claude Code.",
]

kdir, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
k = Kokoro(os.path.join(kdir, "kokoro-v1.0.onnx"), os.path.join(kdir, "voices-v1.0.bin"))
lengths = []
for i, text in enumerate(LINES, 1):
    samples, rate = k.create(text, voice="af_heart", speed=1.0, lang="en-us")
    sf.write(os.path.join(out, f"vo{i:02d}.wav"), samples, rate)
    lengths.append(round(len(samples) / rate, 2))
    print(f"vo{i:02d} {lengths[-1]:6.2f} s")
print(f"total {sum(lengths):.2f} s")
json.dump(lengths, open(os.path.join(out, "lengths.json"), "w"))
