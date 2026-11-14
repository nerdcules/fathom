-- Fathom mini-player: window rules and keys. Installed to
-- ~/.config/hypr/fathom-player.lua and loaded from hyprland.lua by Fathom's
-- install.sh (uninstall.sh removes both).

local player = (os.getenv("HOME") or "") .. "/.local/bin/fathom-player"

-- A small window pinned above everything, on every workspace, in the
-- bottom-right corner. It opens without taking focus from what you're doing.
o.window({ class = "^fathom\\.player$" }, {
  float = true,
  pin = true,
  size = { 640, 360 },
  keep_aspect_ratio = true,
  -- Placed from the size above (640+32, 360+32) rather than window_w/window_h:
  -- Hyprland can place the window before it has been resized, which pushes
  -- it partly off screen.
  move = { "(monitor_w-672)", "(monitor_h-392)" },
  no_initial_focus = true,
})

o.bind("SUPER + ALT + Y", "Play the copied link in the mini-player", player .. " play")
o.bind("SUPER + CTRL + Y", "Close the mini-player", player .. " stop")
