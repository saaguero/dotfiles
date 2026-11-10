-- Mic priority: keep the system default input on the right microphone.
--   1. External Microphone (3.5 mm jack, BOYA BY-M1) whenever it is plugged in
--   2. MacBook Pro Microphone, only with the lid open (in clamshell it records silence)
--   3. Insta360 Link 2C (clamshell fallback)
-- Bluetooth headsets (QC35) are never picked, which also keeps them in stereo A2DP.
--
-- It only reacts to hardware changes (device added/removed, lid/screens, wake) and to
-- the auto-switch macOS does right after one, so a manual pick in Sound settings
-- sticks until the next hardware change.
-- CLI: hs -c "micPriority.apply()"   hs -c "micPriority.enabled = false"

local M = { enabled = true }

local PRIORITY = {
  { name = "External Microphone" },
  { name = "MacBook Pro Microphone", lidOpenOnly = true },
  { name = "Insta360 Link 2C" },
}

-- macOS switches the input a few seconds after a device appears (Bluetooth is slow),
-- so default-input changes inside this window are treated as automatic, not manual.
local HOT_WINDOW = 15
local SETTLE_DELAY = 1.5

local log = hs.logger.new("micPriority", "info")
local hotUntil = 0
local pending

local function lidOpen()
  local out = hs.execute("ioreg -r -k AppleClamshellState -d 1")
  return not out:find('"AppleClamshellState" = Yes', 1, true)
end

function M.apply(reason)
  if not M.enabled then return end
  local open = lidOpen()
  local current = hs.audiodevice.defaultInputDevice()
  for _, entry in ipairs(PRIORITY) do
    if open or not entry.lidOpenOnly then
      local device = hs.audiodevice.findInputByName(entry.name)
      if device then
        if not current or current:uid() ~= device:uid() then
          device:setDefaultInputDevice()
          log.i(string.format("input -> %s (%s, lid %s)", entry.name, reason or "manual",
            open and "open" or "closed"))
          hs.alert.show("🎙 " .. entry.name, 1.5)
        end
        return
      end
    end
  end
  log.w("no preferred input device present")
end

local function schedule(reason)
  if pending then pending:stop() end
  pending = hs.timer.doAfter(SETTLE_DELAY, function()
    pending = nil
    M.apply(reason)
  end)
end

local function hardwareChanged(reason)
  hotUntil = hs.timer.secondsSinceEpoch() + HOT_WINDOW
  schedule(reason)
end

hs.audiodevice.watcher.setCallback(function(event)
  if event == "dev#" then
    hardwareChanged("devices changed")
  elseif event == "dIn " and hs.timer.secondsSinceEpoch() < hotUntil then
    schedule("auto-switch after hardware change")
  end
end)
hs.audiodevice.watcher.start()

-- Lid open/close shows up as the built-in display appearing or disappearing.
M.screenWatcher = hs.screen.watcher.new(function() hardwareChanged("screens changed") end)
M.screenWatcher:start()

M.wakeWatcher = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then hardwareChanged("wake") end
end)
M.wakeWatcher:start()

M.apply("startup")

return M
