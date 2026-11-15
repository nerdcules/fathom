-- Fathom Command Deck: its keys (Deck, its Care page, and the Start menu)
-- and how Hyprland draws it. Installed to
-- ~/.config/hypr/fathom-deck.lua and loaded from hyprland.lua by Fathom's
-- install.sh (uninstall.sh removes both).

local bin = (os.getenv("HOME") or "") .. "/.local/bin/"

-- Frosted glass: blur what's behind the deck's translucent scrim. The deck
-- fades itself in, so no compositor animation on top of that.
hl.layer_rule({ match = { namespace = "^fathom-deck$" }, blur = true, ignore_alpha = 0.1, no_anim = true, animation = "none" })

o.bind("SUPER + ALT + D", "Command Deck", bin .. "fathom-deck")
o.bind("SUPER + ALT + C", "Care: disk, warnings and updates", bin .. "fathom-care")

-- Tap Super on its own for the Start menu, as on Windows. Hyprland skips a
-- release bind when another key or a mouse button was used while Super was
-- held, so Super + anything works as before.
o.bind("SUPER + Super_L", "Start menu", bin .. "fathom-start", { release = true })
o.bind("SUPER + Super_R", "Start menu", bin .. "fathom-start", { release = true })
