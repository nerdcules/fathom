#!/usr/bin/env bash
# Builds the Fathom promo from this folder:
#   make.sh <work dir> <kokoro dir> <out.mp4>
# Steps: made-up data (demo-data.py), the deck pages and Start rendered from
# it (Scene.qml), the title and end cards (Card.qml), the voice (voice.py,
# Kokoro af_heart; the kokoro dir holds kokoro-v1.0.onnx, voices-v1.0.bin
# and a venv with kokoro-onnx), then the cut (assemble.py). The live takes
# must already be in <work dir>/takes (take.sh, which takes over the screen).
# Needs qml6, ffmpeg, magick and python3.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work=$(realpath -m "$1"); kokoro=$(realpath -m "$2"); out=$(realpath -m "$3")
font=$(omarchy font current 2>/dev/null || echo monospace)
[[ -f $work/takes/desk.mp4 && -f $work/takes/look.mp4 ]] || { echo "make.sh: run take.sh $work/takes first" >&2; exit 1; }

"$here/demo-data.py" "$work/data"
mkdir -p "$work/stills"
render() { QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen qml6 "$here/Scene.qml" -- "$work/data" "$1" "$font" "$work/stills/$1.png" "$2" 2>/dev/null; }
# Scale per page: Pulse and Crumbs hold more, so they're drawn smaller.
for page in start deck care sentinel; do render "$page" 1.2; done
for page in pulse crumbs; do render "$page" 1.0; done
for kind in title end; do QT_QPA_PLATFORM=offscreen qml6 "$here/Card.qml" -- "$kind" "$font" "$work/stills/card-$kind.png" 2>/dev/null; done
"$kokoro/venv/bin/python" "$here/voice.py" "$kokoro" "$work/vo"
python3 "$here/assemble.py" "$work" "$out"
