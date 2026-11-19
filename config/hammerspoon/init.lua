-- Hammerspoon config — Santi
-- Stream window router: while streaming, every new window opens on the vertical
-- monitor so nothing accidentally lands on the shared (display-captured) screen.

require("hs.ipc")
hs.ipc.cliInstall("/opt/homebrew")

-- Start at login: the mic priority below must always be running.
hs.autoLaunch(true)

local log = hs.logger.new("streamRouter", "info")

streamRouter = { active = false }

-- The vertical monitor is the portrait one (height > width); the shared ASUS is landscape.
local function verticalScreen()
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:fullFrame()
    if f.h > f.w then return screen end
  end
  return nil
end

local wf = hs.window.filter.new(nil) -- watch all apps
wf:subscribe(hs.window.filter.windowCreated, function(win, appName)
  if not streamRouter.active then return end
  local target = verticalScreen()
  if not target then
    log.w("no portrait screen found, router idle")
    return
  end
  if win:isStandard() and win:screen() ~= target then
    win:moveToScreen(target, false, true, 0)
    log.i("routed new window of " .. (appName or "?") .. " to vertical screen")
  end
end)

function streamRouterSet(on)
  streamRouter.active = on
  hs.alert.show(on and "Stream router ON — new windows → vertical" or "Stream router OFF")
  log.i("streamRouter.active = " .. tostring(on))
end

-- Default input priority (BOYA jack > MacBook mic with lid open > Link 2C).
micPriority = require("mic_priority")

hs.alert.show("Hammerspoon loaded")

-- Voice lookup (hold Right Option + speak), loaded from its own project: ~/projects/voice-lookup
do
  local dir = os.getenv("HOME") .. "/projects/voice-lookup"
  if hs.fs.attributes(dir .. "/voice_lookup.lua") then
    package.path = dir .. "/?.lua;" .. package.path
    voiceLookup = require("voice_lookup")
  end
end
