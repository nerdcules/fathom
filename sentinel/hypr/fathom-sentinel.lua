-- Fathom Sentinel: its key. Installed to ~/.config/hypr/fathom-sentinel.lua
-- and loaded from hyprland.lua by Fathom's install.sh (uninstall.sh removes
-- both). Super+Alt+S is Omarchy's scratchpad, so Sentinel is on X.
local bin = (os.getenv("HOME") or "") .. "/.local/bin/"
o.bind("SUPER + ALT + X", "Sentinel: firewall, sign-ins and network", bin .. "fathom-sentinel")
