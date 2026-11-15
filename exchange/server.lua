-- EXCHANGE SERVER: clearing house + live market. Run ONE per server, on a computer with an ender modem
-- (and optionally a big monitor for the price board).
local dir = fs.getDir(fs.getDir(shell.getRunningProgram()))
package.path = "/" .. dir .. "/?.lua;" .. package.path

local cfg    = require("exchange.config")
local store  = require("common.storage")
local proto  = require("common.protocol")
local proc   = require("common.proc")
local money  = require("common.money")
local items  = require("common.items")
local Exchange = require("exchange.core")

for _, side in ipairs(redstone.getSides()) do
  if peripheral.getType(side) == "modem" then rednet.open(side) end
end
if not rednet.isOpen() then error("No modem attached") end

local datadir = cfg.data_dir or "/exchdata"
fs.makeDir(datadir)
local db = store.open(datadir .. "/exchange.db")

local clients = {}
local function deliver(no, msg)
  local b = db.data.banks[no]
  if not b then return nil end
  clients[no] = clients[no] or proto.client({ dev = "exchange", key = b.key, host = "bank-" .. no, fixed = b.computer })
  clients[no].key = b.key
  return clients[no]:call(msg, 8, msg.type == "x_credit" and 2 or 1)
end

local X = Exchange.new({ db = db.data, save = db.save, clock = proto.now, deliver = deliver, cfg = cfg,
  rand = function() return proto.rand_int(1000000) / 1000000 end })

local function keyfn(devid)
  local no = tonumber(devid:match("^bank:(%d+)$") or "")
  local b = no and db.data.banks[no]
  return b and b.key
end

---------------------------------------------------------------- price board (monitor)
local function board()
  local mon = cfg.monitor and peripheral.wrap(cfg.monitor) or peripheral.find("monitor")
  if not mon then return end
  mon.setTextScale(1)
  local page = 0
  while true do
    sleep(8)
    local now = proto.now()
    local rows = {}
    for id, par in pairs(items.byId) do
      local st = db.data.items[id]
      if st and not par.peg and math.abs(X:flow(id, now)) > 0.5 then
        rows[#rows + 1] = { id = id, pct = X:mid(id, now) / par.base - 1, mid = X:mid(id, now) }
      end
    end
    page = (page + 1) % 3
    local w, h = mon.getSize()
    mon.setBackgroundColor(colors.black); mon.clear()
    local function line(y, text, fg) mon.setCursorPos(1, y); mon.setTextColor(fg or colors.white); mon.write(text:sub(1, w)) end
    if page == 0 or page == 1 then
      table.sort(rows, function(a, b) if page == 0 then return a.pct > b.pct else return a.pct < b.pct end end)
      line(1, page == 0 and "== RISING ==" or "== FALLING ==", colors.yellow)
      for i = 1, math.min(#rows, h - 2) do
        local r = rows[i]
        local txt = string.format("%-" .. math.max(8, w - 18) .. "s %9s %+5.0f%%", items.display(r.id):sub(1, math.max(8, w - 18)), money.short(math.floor(r.mid)), r.pct * 100)
        line(i + 1, txt, r.pct >= 0 and colors.lime or colors.red)
      end
      if #rows == 0 then line(3, "Markets are calm.", colors.lightGray) end
    else
      line(1, "== NEWS & BANKS ==", colors.yellow)
      local y = 2
      for _, e in ipairs(db.data.events) do
        if e.exp > now and y < h then line(y, e.text .. " x" .. e.mult, colors.orange); y = y + 1 end
      end
      for no, b in pairs(db.data.banks) do
        if y < h then local p = db.data.pos[no] or 0; line(y, string.format("%02d %s %s", no, b.name:sub(1, w - 14), money.short(p)), p >= 0 and colors.lime or colors.red); y = y + 1 end
      end
    end
  end
end

---------------------------------------------------------------- housekeeping (events expire / spawn, autosave)
local function tick_loop()
  while true do
    X:tick(proto.now())
    db.save()
    sleep(30)
  end
end

---------------------------------------------------------------- stats bridge poller
local function stats_loop()
  if not cfg.stats_url then return end
  while true do
    local h = http.get(cfg.stats_url)
    if h then
      local data = textutils.unserialiseJSON(h.readAll()); h.close()
      if data then
        local n = X:apply_stats(data, proto.now())
        if n > 0 then db.save() end
      end
    end
    sleep(cfg.stats_poll or 120)
  end
end

---------------------------------------------------------------- admin console
local function cli()
  term.clear(); term.setCursorPos(1, 1)
  print("EXCHANGE online. Type 'help'. Price file " .. items.digest .. " (" .. #items.list .. " items)")
  while true do
    write("> ")
    local line = read() or ""
    local a = {}
    for w in line:gmatch("%S+") do a[#a + 1] = w end
    local cmd, sub = a[1], a[2]
    if cmd == "help" then
      print("bank add <no> <name> [limit_Cr] [computerId] | bank list | bank del <no>")
      print("pos | settle <payerBank> <payeeBank> <Cr> | price <text> | events | event <item|cat> <mult> <min> <text...>")
    elseif cmd == "bank" and sub == "add" and tonumber(a[3]) and a[4] then
      local key = proto.rand_hex(32)
      local ok, err = X:add_bank(tonumber(a[3]), a[4]:gsub("_", " "), key, a[5] and money.parse(a[5]), tonumber(a[6]))
      if ok then print("Bank registered (use _ for spaces in names). Give the owner this exchange_key:"); print("  " .. key) else printError(err) end
    elseif cmd == "bank" and sub == "list" then
      for no, b in pairs(db.data.banks) do print(no, b.name, "limit", money.short(X:limit_of(no)), "position", money.short(db.data.pos[no] or 0)) end
    elseif cmd == "bank" and sub == "del" then db.data.banks[tonumber(a[3])] = nil; db.save(); print("ok")
    elseif cmd == "pos" then
      for no, p in pairs(db.data.pos) do print(string.format("bank %02d  %s Cr  %s", no, money.fmt(p), p < 0 and "(owes the system)" or "(is owed)")) end
    elseif cmd == "settle" and tonumber(a[2]) and tonumber(a[3]) and money.parse(a[4] or "") then
      print(X:settle(tonumber(a[2]), tonumber(a[3]), money.parse(a[4])) and "settled" or "unknown bank")
    elseif cmd == "price" and sub then
      local now, n = proto.now(), 0
      for _, e in ipairs(items.list) do
        if e.id:find(sub, 1, true) and n < 15 then
          n = n + 1
          print(string.format("%-28s base %9s  now %9s  N=%.0f", items.display(e.id):sub(1, 28), money.short(e.base), money.short(math.floor(X:mid(e.id, now))), X:flow(e.id, now)))
        end
      end
    elseif cmd == "events" then
      for _, e in ipairs(db.data.events) do print(e.text, "x" .. e.mult, math.floor((e.exp - proto.now()) / 60000) .. " min left") end
    elseif cmd == "event" and tonumber(a[3]) and tonumber(a[4]) then
      local target = a[2]
      local is_item = target:find(":", 1, true)
      X:add_event(is_item and target or nil, (not is_item) and target or nil, tonumber(a[3]), tonumber(a[4]), table.concat(a, " ", 5), proto.now())
      print("event added")
    elseif cmd and cmd ~= "" then print("unknown command, try 'help'") end
  end
end

proc.spawn(cli)
proc.spawn(board)
proc.spawn(tick_loop)
proc.spawn(stats_loop)
proc.spawn(function()
  proto.serve({ hostname = "exchange", label = "exchange", keyfn = keyfn, spawn = proc.spawn,
    handle = function(devid, msg)
      local no = tonumber(devid:match("^bank:(%d+)$"))
      return X:handle(no, msg)
    end })
end)
proc.run()
