-- Fathom Command Deck: its key and how Hyprland draws it. Installed to
-- ~/.config/hypr/fathom-deck.lua and loaded from hyprland.lua by Fathom's
-- install.sh (uninstall.sh removes both).

local deck = (os.getenv("HOME") or "") .. "/.local/bin/fathom-deck"

-- Frosted glass: blur what's behind the deck's translucent scrim. The deck
-- fades itself in, so no compositor animation on top of that.
hl.layer_rule({ match = { namespace = "^fathom-deck$" }, blur = true, ignore_alpha = 0.1, no_anim = true, animation = "none" })

o.bind("SUPER + ALT + D", "Command Deck", deck .. " toggle")
