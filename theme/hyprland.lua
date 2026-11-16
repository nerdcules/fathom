-- Fathom's Hyprland look. Omarchy would generate the border colours from
-- colors.toml; a theme that ships this file replaces that, so they're here
-- as Omarchy generated them, with the rounding added.
--
-- 22 px corners on windows, as on the Start menu's panel. Omarchy's own
-- panels, menu and notifications take their corners from this rounding too
-- (the shell's Style.cornerRadius), so everything shares one radius.

local active_border_color = { colors = { "rgba(4cc9f0ee)", "rgba(9d8cffee)" }, angle = 45 }
local inactive_border_color = "rgba(1f3350aa)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  decoration = {
    rounding = 22,
  },
})
