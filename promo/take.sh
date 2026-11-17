#!/usr/bin/env bash
# Records the promo's two live takes on this laptop:
#   take.sh <out dir>   -> desk.mp4 (the desktop, Alt+Tab, Task view, Snap
#                          layouts, Quick settings) and look.mp4 (Personalise)
#
# It takes over the screen for about a minute: it parks every open window on
# a hidden special workspace (Task view and Alt+Tab leave those out), opens
# harmless windows to film (Fathom's GitHub page in a throwaway Chromium
# profile, its README, btop, Files), turns on Focus so no notification
# shows, and records with gpu-screen-recorder. Everything goes back on exit,
# even after an error: your windows and workspace, Focus, and your look.
# Synthetic keys don't trigger Hyprland binds, so the desk is driven through
# its commands and Lua functions.
set -euo pipefail

out=$(realpath -m "${1:?usage: take.sh <out dir>}")
mkdir -p "$out"
work=$(mktemp -d)
PARK="special:fathompromo"
look=$HOME/.local/bin/fathom-look
desk=$HOME/.local/bin/fathom-desk

lua() { hyprctl dispatch "$1" >/dev/null; }
# Fathom's own Lua functions run, then hyprctl complains (exit 7) that they
# returned no dispatcher; that's expected.
call() { hyprctl dispatch "$1" >/dev/null 2>&1 || true; }
quote() { printf '"%s"' "$1"; }

# What to put back.
start_ws=$(hyprctl activeworkspace -j | jq -r .name)
mapfile -t parked < <(hyprctl clients -j | jq -r '.[] | select(.workspace.name | startswith("special") | not) | "\(.address) \(.workspace.name)"')
saved_look=$("$look" state | jq -c .look)
focus_was=$("$HOME/.local/bin/fathom-start" menu | jq -r .status.focus)
staged=()
recorder=""

restore() {
  set +e
  [[ -n $recorder ]] && kill -INT "$recorder" 2>/dev/null && wait "$recorder" 2>/dev/null
  omarchy-shell -q shell hide fathom.desk >/dev/null 2>&1
  for addr in "${staged[@]}"; do lua "hl.dsp.window.close({ window = $(quote "address:$addr") })"; done
  for line in "${parked[@]}"; do
    read -r addr ws <<<"$line"
    lua "hl.dsp.window.move({ workspace = $(quote "$ws"), follow = false, window = $(quote "address:$addr") })"
  done
  lua "hl.dsp.focus({ workspace = $(quote "$start_ws") })"
  "$look" set accent "$(jq -r .accent <<<"$saved_look")" frame "$(jq -r .frame <<<"$saved_look")" \
    frame-style "$(jq -r .frameStyle <<<"$saved_look")" corners "$(jq -r .corners <<<"$saved_look")" \
    opacity "$(jq -r .opacity <<<"$saved_look")" glow "$(jq -r 'if .glow then "on" else "off" end' <<<"$saved_look")" >/dev/null
  [[ $focus_was == false && $("$HOME/.local/bin/fathom-start" menu | jq -r .status.focus) == true ]] &&
    "$HOME/.local/bin/fathom-start" focus >/dev/null
  rm -rf "$work"
  echo "Put back: ${#parked[@]} windows on their workspaces, workspace $start_ws, Focus, and your look."
}
trap restore EXIT

# Open a program on a workspace and wait for its window; prints its address.
open_on() {
  local ws=$1 class=$2 cmd=$3 before addr i
  before=$(hyprctl clients -j | jq -c '[.[].address]')
  lua "hl.dsp.exec_cmd($(quote "$cmd"), { workspace = $(quote "$ws silent") })"
  for i in $(seq 1 60); do
    addr=$(hyprctl clients -j | jq -r --argjson before "$before" --arg class "$class" \
      '[.[] | select(.class == $class and (.address as $a | $before | index($a) | not))][0].address // empty')
    [[ -n $addr ]] && { echo "$addr"; return; }
    sleep 0.25
  done
  echo "take.sh: $class didn't open" >&2
  return 1
}

record() {
  gpu-screen-recorder -w eDP-1 -f 30 -cursor no -o "$1" >/dev/null 2>&1 &
  recorder=$!
  sleep 1.5
}

stop_recording() {
  kill -INT "$recorder"
  wait "$recorder" || true
  recorder=""
}

# Park your windows and start from Fathom's own look, quietly.
for line in "${parked[@]}"; do
  lua "hl.dsp.window.move({ workspace = $(quote "$PARK"), follow = false, window = $(quote "address:${line%% *}") })"
done
[[ $focus_was == false ]] && "$HOME/.local/bin/fathom-start" focus >/dev/null
"$look" reset >/dev/null

staged+=("$(open_on 2 foot "foot --app-id foot -e btop")")
staged+=("$(open_on 2 org.gnome.Nautilus "nautilus --new-window $HOME/Work/fathom")")
staged+=("$(open_on 1 chromium "chromium --user-data-dir=$work/chromium --no-first-run --no-default-browser-check --new-window https://github.com/nerdcules/fathom")")
staged+=("$(open_on 1 foot "foot --app-id foot -D $HOME/Work/fathom nvim -R README.md")")
lua 'hl.dsp.focus({ workspace = "1" })'
sleep 4   # the page loads, the windows settle

# Take 1: the desktop, then the desk.
record "$out/desk.mp4"
sleep 6
# Times from the recording's start: the desktop 1.5-7.5 s, Alt+Tab
# 7.5-11.3, Task view 11.8-15.1, Snap layouts 15.1-17.8, Quick settings
# 17.8-21.4 (assemble.py cuts at these).
call 'fathom_desk.switch(1)()'; sleep 0.9
call 'fathom_desk.switch(1)()'; sleep 0.9
call 'fathom_desk.switch(1)()'; sleep 1.0
call 'fathom_desk.finish()'; sleep 1.0
lua 'hl.dsp.focus({ workspace = "1" })'; sleep 0.5
"$desk" tasks; sleep 2.8
"$desk" tasks; sleep 0.5
"$desk" snap; sleep 2.2
"$desk" snap; sleep 0.5
"$desk" quick; sleep 2.8
"$desk" quick; sleep 0.8
stop_recording

# Take 2: Personalise, over windows and Quick settings. From the
# recording's start: Fathom's look until 3.5 s, then rose, green and violet
# 2.5 s apart, and Fathom's look again from 11 s.
"$desk" quick; sleep 1.5
record "$out/look.mp4"
sleep 2
"$look" set accent '#ff6b81' frame '#ffb547' corners 10 >/dev/null; sleep 2.5
"$look" set accent '#3ddc97' frame '#4cc9f0' corners 0 >/dev/null; sleep 2.5
"$look" set accent '#9d8cff' frame '#ff6b81' corners 30 >/dev/null; sleep 2.5
"$look" reset >/dev/null; sleep 2.5
stop_recording
"$desk" quick

ls -la "$out"/desk.mp4 "$out"/look.mp4
