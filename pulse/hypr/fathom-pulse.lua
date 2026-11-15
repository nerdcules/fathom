-- Fathom Pulse: its key. Installed to ~/.config/hypr/fathom-pulse.lua and
-- loaded from hyprland.lua by Fathom's install.sh (uninstall.sh removes both).
local bin = (os.getenv("HOME") or "") .. "/.local/bin/"
o.bind("SUPER + ALT + P", "Pulse: what calls what in your stack", bin .. "fathom-pulse")
