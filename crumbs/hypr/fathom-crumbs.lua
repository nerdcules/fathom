-- Fathom Crumbs: its key. Installed to ~/.config/hypr/fathom-crumbs.lua and
-- loaded from hyprland.lua by Fathom's install.sh (uninstall.sh removes both).

local bin = (os.getenv("HOME") or "") .. "/.local/bin/"

o.bind("SUPER + ALT + O", "Crumbs: cookies and trackers", bin .. "fathom-crumbs")
