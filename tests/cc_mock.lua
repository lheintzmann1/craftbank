-- Minimal fake of the ComputerCraft environment, enough to run atm.lua / shop.lua headless.
-- A script of "button ids" drives the touch UI; inventories are fake chests/barrels.
local M = {}

function M.install()
  local color_n = 0
  colors = setmetatable({}, { __index = function(t, k) color_n = color_n + 1; rawset(t, k, 2 ^ color_n); return t[k] end })
  printError = function(...) io.stderr:write("[printError] ", table.concat({ ... }, " "), "\n") end
  textutils = { serialise = function(t) return require("common.serial").encode(t) end }
  redstone = { getSides = function() return { "top" } end }
  rednet = { open = function() end, isOpen = function() return true end }
  shell = { getRunningProgram = function() return M.program end }
  fs = { getDir = function(p) return p:match("^(.*)/[^/]*$") or "" end }

  M.invs = {}
  M.actions, M.log = {}, {}
  local mon = { getSize = function() return 15, 10 end }
  for _, f in ipairs({ "setTextScale", "setBackgroundColor", "setTextColor", "setCursorPos", "write", "clear" }) do mon[f] = function() end end
  M.mon = mon

  peripheral = {
    getNames = function() local n = { "monitor_0" }; for k in pairs(M.invs) do n[#n + 1] = k end; return n end,
    getType = function(n) return n == "monitor_0" and "monitor" or "inventory" end,
    find = function(t) if t == "monitor" then return mon end end,
    wrap = function() return mon end,
    getName = function() return "monitor_0" end,
    call = function(name, method, ...) return M.invs[name][method](M.invs[name], ...) end,
  }

  os.startTimer = function() return 1 end
  os.cancelTimer = function() end
  os.pullEvent = function()
    local act = table.remove(M.actions, 1)
    if act == nil then error("Terminated", 0) end
    if type(act) == "function" then act = act() end
    if act == "timeout" then return "timer", 1 end
    local ui = M.ui
    for _, b in ipairs(ui.btns) do
      if b.id == act then return "monitor_touch", "monitor_0", b.x + math.floor(b.w / 2), b.y + math.floor(b.h / 2) end
    end
    local ids = {}
    for _, b in ipairs(ui.btns) do ids[#ids + 1] = tostring(b.id) end
    error("action '" .. tostring(act) .. "' not on screen; available: " .. table.concat(ids, ","), 0)
  end
end

-- fake inventory with CC-like methods
function M.inventory(name, size)
  local inv = { size_ = size or 27, slots = {} }
  function inv:size() return self.size_ end
  function inv:list() local r = {}; for s, st in pairs(self.slots) do r[s] = { name = st.name, count = st.count } end; return r end
  function inv:pushItems(to, slot, limit)
    local st = self.slots[slot]; if not st then return 0 end
    local dst, left = M.invs[to], math.min(limit or st.count, st.count)
    local moved = 0
    for s = 1, dst.size_ do
      if left <= 0 then break end
      local d = dst.slots[s]
      if d and d.name == st.name and d.count < 64 then
        local n = math.min(64 - d.count, left); d.count = d.count + n; moved = moved + n; left = left - n
      end
    end
    for s = 1, dst.size_ do
      if left <= 0 then break end
      if not dst.slots[s] then
        local n = math.min(64, left); dst.slots[s] = { name = st.name, count = n }; moved = moved + n; left = left - n
      end
    end
    st.count = st.count - moved
    if st.count <= 0 then self.slots[slot] = nil end
    return moved
  end
  function inv:add(id, count)
    for s = 1, self.size_ do
      while count > 0 and not self.slots[s] do self.slots[s] = { name = id, count = math.min(64, count) }; count = count - math.min(64, count) end
    end
  end
  function inv:total(id) local t = 0; for _, st in pairs(self.slots) do if st.name == id then t = t + st.count end end; return t end
  M.invs[name] = inv
  return inv
end

-- run a program with a script of actions; `ui_module` must be captured through M.capture_ui
function M.capture_ui()
  local real = require("common.ui")
  local wrapper = setmetatable({}, { __index = real })
  wrapper.new = function(...) local u = real.new(...); M.ui = u; return u end
  package.loaded["common.ui"] = wrapper
end

return M
