#!/usr/bin/env bash
# Draws crumbs/preview.jpg, the README's picture of Crumbs, from made-up
# browsing (make-demo.py) rendered by the real page (Preview.qml). Needs
# qml6 (qt6-declarative) and magick.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
font=$(omarchy font current 2>/dev/null || echo monospace)
"$here/make-demo.py" "$work"
QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen qml6 "$here/Preview.qml" -- "$work" "$font" "$work/crumbs.png"
magick "$work/crumbs.png" -resize 1600x -quality 85 "$here/../preview.jpg"
echo "Wrote $(cd "$here/.." && pwd)/preview.jpg"
