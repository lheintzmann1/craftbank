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
local webhook = require("common.webhook")
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

local function notify_handler(event, data)
  if cfg.discord_webhook then
    if event == "event" then
      webhook.notify_event(cfg.discord_webhook, data.text or "", data.mult or 1, data.mins or 0)
    end
  end
end

local X = Exchange.new({ db = db.data, save = db.save, clock = proto.now, deliver = deliver, cfg = cfg,
  rand = function() return proto.rand_int(1000000) / 1000000 end,
  notify = notify_handler })

local function keyfn(devid)
  local no = tonumber(devid:match("^bank:(%d+)$") or "")
  local b = no and db.data.banks[no]
  return b and b.key
end

---------------------------------------------------------------- sparkline helper
-- ASCII sparkline characters (8 levels from empty to full)
local SPARKLINE_CHARS = {" ", "\128", "\129", "\130", "\131", "\132", "\133", "\134", "\135"}
-- Alternative if extended ASCII doesn't work:
-- local SPARKLINE_CHARS = {" ", ".", ":", "-", "=", "*", "#", "@", "█"}

local function render_sparkline(hist, w)
  if not hist or #hist == 0 then return "" end
  local min_val, max_val = hist[1], hist[1]
  for _, v in ipairs(hist) do
    min_val = math.min(min_val, v)
    max_val = math.max(max_val, v)
  end
  local range = max_val - min_val
  if range == 0 then range = 1 end
  local sparkline = ""
  for _, v in ipairs(hist) do
    local idx = math.floor(((v - min_val) / range) * 8) + 1
    sparkline = sparkline .. SPARKLINE_CHARS[math.min(9, math.max(1, idx))]
  end
  -- Pad or truncate to width
  if #sparkline < w then sparkline = sparkline .. string.rep(" ", w - #sparkline)
  elseif #sparkline > w then sparkline = sparkline:sub(1, w) end
  return sparkline
end

---------------------------------------------------------------- price board (monitor)
local function board()
  local mon = cfg.monitor and peripheral.wrap(cfg.monitor) or peripheral.find("monitor")
  if not mon then return end
  mon.setTextScale(1)
  local page = 0
  local spark_w = 10  -- width of sparkline
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
    page = (page + 1) % 4  -- added a new page for index
    local w, h = mon.getSize()
    mon.setBackgroundColor(colors.black); mon.clear()
    local function line(y, text, fg) mon.setCursorPos(1, y); mon.setTextColor(fg or colors.white); mon.write(text:sub(1, w)) end
    if page == 0 or page == 1 then
      table.sort(rows, function(a, b) if page == 0 then return a.pct > b.pct else return a.pct < b.pct end end)
      line(1, page == 0 and "== RISING ==" or "== FALLING ==", colors.yellow)
      for i = 1, math.min(#rows, h - 2) do
        local r = rows[i]
        -- Get price history for sparkline
        local hist = {}
        if db.data.price_history and db.data.price_history[r.id] then
          for _, entry in ipairs(db.data.price_history[r.id]) do
            hist[#hist + 1] = entry.mid
          end
        end
        local spark = render_sparkline(hist, spark_w)
        local item_name = items.display(r.id):sub(1, math.max(8, w - 22 - spark_w))
        local txt = string.format("%s%s %9s %+5.0f%%", spark, item_name, money.short(math.floor(r.mid)), r.pct * 100)
        line(i + 1, txt, r.pct >= 0 and colors.lime or colors.red)
      end
      if #rows == 0 then line(3, "Markets are calm.", colors.lightGray) end
    elseif page == 2 then
      line(1, "== NEWS & BANKS ==", colors.yellow)
      local y = 2
      for _, e in ipairs(db.data.events) do
        if e.exp > now and y < h then line(y, e.text .. " x" .. e.mult, colors.orange); y = y + 1 end
      end
      for no, b in pairs(db.data.banks) do
        if y < h then local p = db.data.pos[no] or 0; line(y, string.format("%02d %s %s", no, b.name:sub(1, w - 14), money.short(p)), p >= 0 and colors.lime or colors.red); y = y + 1 end
      end
    else -- page 3: Economy Index
      line(1, "== ECONOMY INDEX ==", colors.yellow)
      local index = X:economy_index(now)
      local index_hist = {}
      if db.data.index_history then
        for _, entry in ipairs(db.data.index_history) do
          index_hist[#index_hist + 1] = entry.index
        end
      end
      local index_spark = render_sparkline(index_hist, spark_w)
      line(2, "Index: " .. money.short(math.floor(index or 0)) .. " Cr")
      line(3, "Trend: " .. index_spark)
      
      -- Show top movers
      line(5, "Top Movers:", colors.yellow)
      local all_items = {}
      for id, par in pairs(items.byId) do
        if not par.peg then
          local mid = X:mid(id, now)
          local base = par.base
          all_items[#all_items + 1] = { id = id, pct = (mid - base) / base * 100, mid = mid }
        end
      end
      table.sort(all_items, function(a, b) return math.abs(a.pct) > math.abs(b.pct) end)
      for i = 1, math.min(5, h - 6) do
        local item = all_items[i]
        local display = items.display(item.id):sub(1, w - 20)
        local pct_str = string.format("%+5.0f%%", item.pct)
        line(5 + i, string.format("  %s %s", display, pct_str), item.pct >= 0 and colors.lime or colors.red)
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
      local text = table.concat(a, " ", 5)
      local mult = tonumber(a[3])
      local mins = tonumber(a[4])
      X:add_event(is_item and target or nil, (not is_item) and target or nil, mult, mins, text, proto.now())
      print("event added")
      -- Notify Discord if webhook is configured
      if cfg.discord_webhook then
        webhook.notify_event(cfg.discord_webhook, text, mult, mins)
      end
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
