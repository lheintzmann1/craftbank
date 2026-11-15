-- Tiny cooperative scheduler so a server can handle many requests at once.
-- Every task receives every event (like parallel), and may block on rednet/timers.
local M = {}
local tasks = {}

local function step(t, ...)
  local ok, filter = coroutine.resume(t.co, ...)
  if not ok then
    printError("[task error] " .. tostring(filter))
    t.dead = true
  elseif coroutine.status(t.co) == "dead" then t.dead = true
  else t.filter = filter end
end

function M.spawn(fn, ...)
  local t = { co = coroutine.create(fn) }
  tasks[#tasks + 1] = t
  step(t, ...)
  return t
end

-- Run until the user terminates (Ctrl+T).
function M.run()
  while true do
    local ev = table.pack(os.pullEventRaw())
    if ev[1] == "terminate" then return end
    local snapshot = {}
    for i, t in ipairs(tasks) do snapshot[i] = t end
    for _, t in ipairs(snapshot) do
      if not t.dead and (t.filter == nil or t.filter == ev[1]) then step(t, table.unpack(ev, 1, ev.n)) end
    end
    local alive = {}
    for _, t in ipairs(tasks) do if not t.dead then alive[#alive + 1] = t end end
    tasks = alive
  end
end

return M
