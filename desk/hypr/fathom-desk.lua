-- Fathom desk: Alt+Tab, Task view, Snap layouts and Quick settings, and how
-- Hyprland draws them. Installed to ~/.config/hypr/fathom-desk.lua and
-- loaded from hyprland.lua by Fathom's install.sh (uninstall.sh removes both).

local bin = (os.getenv("HOME") or "") .. "/.local/bin/"

-- Frosted glass behind the desk's panels; the desk fades itself in.
hl.layer_rule({ match = { namespace = "^fathom-desk$" }, blur = true, ignore_alpha = 0.1, no_anim = true, animation = "none" })

-- ---------------------------------------------------------------- Alt+Tab
--
-- Alt+Tab opens the switcher with the window used before this one picked;
-- Tab again (Alt still held) steps on, Shift+Tab steps back, and letting go
-- of Alt brings the picked window forward. Esc (or Alt+Esc) leaves things
-- as they were.
--
-- While the switcher is up, Hyprland is in the "fathom-switch" submap, so
-- Tab reaches the switcher and nothing else. Letting go of Alt is caught
-- three ways, whichever comes first: a timer here that watches the key
-- (when Hyprland reports it held), a release bind, and the switcher itself,
-- which has the keyboard once it shows. A last timer leaves the submap
-- if nothing has happened for 8 seconds, so the keyboard can't be left in it.

local function shell_call(method, arg)
  hl.exec_cmd("omarchy-shell -q shell call fathom.desk " .. method .. " " .. arg)
end

local function alt_down()
  return hl.is_key_down("Alt_L") or hl.is_key_down("Alt_R")
end

local watch = nil
local failsafe = nil

local function stop_watching()
  if watch then watch:set_enabled(false) end
  if failsafe then failsafe:set_enabled(false) end
end

local function leave()
  stop_watching()
  if hl.get_current_submap() == "fathom-switch" then
    hl.dispatch(hl.dsp.submap("reset"))
  end
end

local function finish()
  if hl.get_current_submap() ~= "fathom-switch" then
    stop_watching()
    return
  end
  leave()
  shell_call("commit", "go")
end

local function cancel()
  leave()
  shell_call("cancel", "go")
end

local function switch(delta)
  return function()
    local opening = hl.get_current_submap() ~= "fathom-switch"
    shell_call("step", tostring(delta))
    if opening then
      hl.dispatch(hl.dsp.submap("fathom-switch"))
      if alt_down() then
        if watch then
          watch:set_enabled(true)
        else
          watch = hl.timer(function()
            if not alt_down() then finish() end
          end, { timeout = 25, type = "repeat" })
        end
      end
    end
    if failsafe then
      failsafe:set_enabled(false)
      failsafe:set_timeout(8000)
      failsafe:set_enabled(true)
    else
      failsafe = hl.timer(function() if hl.get_current_submap() == "fathom-switch" then cancel() end end,
        { timeout = 8000, type = "oneshot" })
    end
  end
end

-- The same steps by name, for scripts and tests:
--   hyprctl dispatch 'fathom_desk.switch(1)()'
fathom_desk = { switch = switch, finish = finish, cancel = cancel }

-- Rebind first: unbinding a key takes it out of every submap.
o.rebind("ALT + TAB", "Switch windows", switch(1))
o.rebind("ALT + SHIFT + TAB", "Switch windows, backwards", switch(-1))

hl.define_submap("fathom-switch", function()
  hl.bind("ALT + TAB", switch(1), { description = "Next window" })
  hl.bind("ALT + SHIFT + TAB", switch(-1), { description = "Previous window" })
  hl.bind("ALT + RIGHT", switch(1), { description = "Next window" })
  hl.bind("ALT + LEFT", switch(-1), { description = "Previous window" })
  hl.bind("ALT + Alt_L", finish, { release = true, description = "Bring the window forward" })
  hl.bind("ALT + Alt_R", finish, { release = true, description = "Bring the window forward" })
  hl.bind("Alt_L", finish, { release = true, description = "Bring the window forward" })
  hl.bind("ALT + RETURN", finish, { description = "Bring the window forward" })
  hl.bind("RETURN", finish, { description = "Bring the window forward" })
  hl.bind("ALT + ESCAPE", cancel, { description = "Leave windows as they were" })
  hl.bind("ESCAPE", cancel, { description = "Leave windows as they were" })
end)


-- ---------------------------------------------------------------- views

-- ---------------------------------------------------------------- Super+Tab
--
-- Task view on Super+Tab, as on Windows. Omarchy's "Next workspace" was
-- here; Super+Shift+Tab (previous) and Super+Ctrl+Tab (former) stay.
--
-- Super+Tab opens Task view on this workspace. Tab again, Super still held,
-- looks at the next workspace (Shift+Tab the one before), and letting go of
-- Super goes there. A plain tap leaves Task view open for the mouse or the
-- keys (Tab, Enter, Esc; see TaskView.qml). While Super is held after the
-- first press, Hyprland is in the "fathom-tasks" submap; letting go is
-- caught by a timer watching the key, by Task view itself, and a last timer
-- leaves the submap after 8 seconds with nothing done, as Alt+Tab does.

local function super_down()
  return hl.is_key_down("Super_L") or hl.is_key_down("Super_R")
end

local tasks_watch = nil
local tasks_failsafe = nil

local function tasks_stop_watching()
  if tasks_watch then tasks_watch:set_enabled(false) end
  if tasks_failsafe then tasks_failsafe:set_enabled(false) end
end

local function tasks_leave()
  tasks_stop_watching()
  if hl.get_current_submap() == "fathom-tasks" then
    hl.dispatch(hl.dsp.submap("reset"))
  end
end

local function tasks_release()
  if hl.get_current_submap() ~= "fathom-tasks" then
    tasks_stop_watching()
    return
  end
  tasks_leave()
  shell_call("tasksRelease", "go")
end

local function tasks_cancel()
  tasks_leave()
  shell_call("tasksCancel", "go")
end

local function tasks(delta)
  return function()
    shell_call("tasks", tostring(delta))
    if hl.get_current_submap() ~= "fathom-tasks" and super_down() then
      hl.dispatch(hl.dsp.submap("fathom-tasks"))
      if tasks_watch then
        tasks_watch:set_enabled(true)
      else
        tasks_watch = hl.timer(function()
          if not super_down() then tasks_release() end
        end, { timeout = 25, type = "repeat" })
      end
    end
    if tasks_failsafe then
      tasks_failsafe:set_enabled(false)
      tasks_failsafe:set_timeout(8000)
      tasks_failsafe:set_enabled(true)
    else
      tasks_failsafe = hl.timer(function() if hl.get_current_submap() == "fathom-tasks" then tasks_leave() end end,
        { timeout = 8000, type = "oneshot" })
    end
  end
end

-- For scripts and tests: hyprctl dispatch 'fathom_desk.tasks(1)()'
fathom_desk.tasks = tasks
fathom_desk.tasks_release = tasks_release
fathom_desk.tasks_cancel = tasks_cancel

o.rebind("SUPER + TAB", "Task view: every window and workspace", tasks(1))

hl.define_submap("fathom-tasks", function()
  hl.bind("SUPER + TAB", tasks(1), { description = "Next workspace" })
  hl.bind("SUPER + SHIFT + TAB", tasks(-1), { description = "Previous workspace" })
  hl.bind("SUPER + Super_L", tasks_release, { release = true, description = "Go to the workspace" })
  hl.bind("SUPER + Super_R", tasks_release, { release = true, description = "Go to the workspace" })
  hl.bind("Super_L", tasks_release, { release = true, description = "Go to the workspace" })
  hl.bind("SUPER + ESCAPE", tasks_cancel, { description = "Close Task view" })
  hl.bind("ESCAPE", tasks_cancel, { description = "Close Task view" })
end)

-- ---------------------------------------------------------------- the rest

o.bind("SUPER + Z", "Snap layouts for this window", bin .. "fathom-desk snap")
o.bind("SUPER + ALT + A", "Quick settings", bin .. "fathom-desk quick")

-- Omarchy's keys for its audio, Bluetooth, network and power panels (#14):
-- the bar's cluster takes those four off the bar, so their keys open Quick
-- settings instead, on the list that matches. o.rebind takes Omarchy's off
-- first (o.bind would add a second bind, and both would run: seen in the
-- test VM); uninstall.sh's Hyprland reload puts them back.
o.rebind("SUPER + CTRL + A", "Quick settings", bin .. "fathom-desk quick")
o.rebind("SUPER + CTRL + B", "Bluetooth", bin .. "fathom-desk quick bluetooth")
o.rebind("SUPER + CTRL + N", "Network", bin .. "fathom-desk quick wifi")
o.rebind("SUPER + CTRL + P", "Quick settings", bin .. "fathom-desk quick")
