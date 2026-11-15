-- SHOP: sells stock to players and/or buys items from them, at live market prices.
-- Payment by one-time PAY CODE (generated at an ATM): the shop never sees a PIN or an account balance.
local dir = fs.getDir(fs.getDir(shell.getRunningProgram()))
package.path = "/" .. dir .. "/?.lua;" .. package.path

local cfg     = require("shop.config")
local money   = require("common.money")
local proto   = require("common.protocol")
local store   = require("common.storage")
local pricing = require("common.pricing")
local items   = require("common.items")
local UI      = require("common.ui")
local inv     = require("common.inventory")

for _, side in ipairs(redstone.getSides()) do
  if peripheral.getType(side) == "modem" then rednet.open(side) end
end
local mon = cfg.monitor and peripheral.wrap(cfg.monitor) or peripheral.find("monitor")
if not mon then error("No monitor found") end
mon.setTextScale(cfg.text_scale or 0.5)
local ui = UI.new(mon, cfg.monitor or peripheral.getName(mon))

local io_chest = cfg.io_chest or inv.names("chest")[1]
local stock_names = cfg.stock or inv.names("barrel")
local mode = cfg.mode or "both"
local spread = cfg.spread or 0.08
local link = proto.client({ dev = cfg.device_id, key = cfg.device_key, host = "bank-" .. cfg.bank_no, fixed = cfg.bank_computer })
local PENDING = fs.getDir(shell.getRunningProgram()) .. "/pending.log"
local mismatch = false

local function call(msg, timeout, tries) return link:call(msg, timeout or 8, tries or 1) end
local function reason(r) if not r then return "Bank unreachable. Try later." end; return r.msg or r.err or "Error" end
local function fmt_code(s) return #s > 2 and (s:sub(1, 2) .. " " .. s:sub(3)) or s end
local function fmt_acct(s) return #s > 2 and (s:sub(1, 2) .. "-" .. s:sub(3)) or s end
local function note_pending(kind, ref, amount, extra)
  store.append(PENDING, textutils.serialise({ t = proto.now(), kind = kind, ref = ref, amount = amount, extra = extra }, { compact = true }))
end

---------------------------------------------------------------- market access
-- returns { [id] = {N, ev} }; falls back to base prices (N=0) if the exchange is unreachable
local function fetch_states(ids)
  local states = {}
  local r = call({ type = "market", op = "prices", args = { items = ids } }, 6)
  if r and r.ok then
    states = r.items
    mismatch = (r.digest ~= items.digest)
  end
  for _, id in ipairs(ids) do states[id] = states[id] or { 0, 1 } end
  return states
end

-- total price in cents for `qty` units. side: "buy" = player buys from us, "sell" = player sells to us
local function total(id, states, side, qty)
  local ov = cfg.overrides and cfg.overrides[id]
  if ov and ov[side] then return ov[side] * qty end
  local st = states[id]
  return pricing.quote(items.byId[id], st[1], st[2], side, qty, spread)
end

local function report(id, side, qty)
  call({ type = "market", op = "report", args = { item = id, side = side, qty = qty } }, 4)
end

local function take_stock(id, qty)
  local left = qty
  for _, s in ipairs(stock_names) do
    if left <= 0 then break end
    left = left - inv.move(s, { io_chest }, id, left)
  end
  return qty - left
end

---------------------------------------------------------------- player BUYS
local function buy_item(id, have, states)
  local room = inv.free_space(io_chest, id)
  local maxq = math.min(have, room, cfg.max_per_order or 576)
  if maxq < 1 then return ui:message("Sorry", room < 1 and "Output chest is full." or "Sold out.", "bad") end
  local q = ui:stepper("Buy", { name = items.display(id), line = "stock " .. have, max = maxq,
    total = function(n) return money.short(total(id, states, "buy", n)) .. " Cr" end })
  if not q then return end
  local cost = total(id, states, "buy", q)
  local code = ui:keypad("Pay code", { maxlen = 8, minlen = 8, hint = "8-digit code", fmt = fmt_code, timeout = 90 })
  if not code then return end
  ui:splash("Paying", money.short(cost) .. " Cr")
  if inv.count(stock_names, id) < q then return ui:message("Sorry", "Stock changed.", "bad") end
  local ref = proto.rand_hex(10)
  local r = call({ type = "redeem", code = code, amount = cost, memo = items.display(id):sub(1, 20), ref = ref }, 14)
  if r and r.ok then
    local moved = take_stock(id, q)
    if moved < q then note_pending("short_dispense", ref, cost, { id = id, wanted = q, moved = moved }) end
    report(id, "buy", moved)
    ui:message("Thank you!", { moved .. " x " .. items.display(id), "Take them from the chest." }, "ok")
  elseif not r or r.err == "unknown" then
    note_pending("redeem_unknown", ref, cost, { id = id, qty = q })
    ui:message("Unsure", { "Payment status unknown.", "No items given.", "Ask your bank (ref " .. ref .. ")" }, "bad")
  else ui:message("Declined", reason(r), "bad") end
end

local function player_buy()
  while true do
    ui:splash("Shop")
    local stock = inv.tally(stock_names, true)
    local ids = {}
    for id, c in pairs(stock) do if items.byId[id] and c > 0 then ids[#ids + 1] = id end end
    if #ids == 0 then return ui:message("Sold out", "Nothing for sale right now.", "bad") end
    table.sort(ids, function(a, b) return items.display(a) < items.display(b) end)
    local states = fetch_states(ids)
    local rows = {}
    for _, id in ipairs(ids) do rows[#rows + 1] = { id = id, l = items.display(id), r = money.short(total(id, states, "buy", 1)) } end
    local sel = ui:list("Buy", rows)
    if not sel or sel == "back" then return end
    buy_item(sel, stock[sel], states)
  end
end

---------------------------------------------------------------- player SELLS
local function max_stock(id)
  if cfg.buy_list then return cfg.buy_list[id] end
  return cfg.max_stock_default or 2048
end

local function player_sell()
  if not ui:confirm("Sell", "Put items in the chest, then tap OK", "OK", "Cancel") then return end
  ui:splash("Sell", "Checking...")
  local contents = inv.tally({ io_chest }, true)
  local stock = inv.tally(stock_names, true)
  local offer, ids = {}, {}
  for id, c in pairs(contents) do
    local cap = max_stock(id)
    if items.byId[id] and cap then
      local n = math.min(c, cap - (stock[id] or 0))
      if n > 0 then offer[id] = n; ids[#ids + 1] = id end
    end
  end
  if #ids == 0 then return ui:message("No thanks", "I don't buy these (or I'm full). Take your items back.", "bad") end
  table.sort(ids, function(a, b) return items.display(a) < items.display(b) end)
  local states = fetch_states(ids)

  local sum, rows = 0, {}
  for _, id in ipairs(ids) do
    local t = total(id, states, "sell", offer[id]); sum = sum + t
    rows[#rows + 1] = { l = offer[id] .. "x " .. items.display(id), r = money.short(t) }
  end
  ui:list("Offer " .. money.short(sum), rows)
  if not ui:confirm("Sell all?", { "Receive " .. money.short(sum) .. " Cr" }, "Sell", "Cancel") then return end

  local acct = ui:keypad("Your account", { maxlen = 8, minlen = 8, hint = "BB-NNNNNN", fmt = fmt_acct, timeout = 60 })
  if not acct then return end
  ui:splash("Sell", "Checking...")
  local l = call({ type = "lookup", acct = acct }, 8)
  if not (l and l.ok) then return ui:message("Not found", reason(l), "bad") end
  if not ui:confirm("Pay to", { l.name, l.bank or "" }, "Yes", "No") then return end

  -- 1) take the items into stock, 2) pay, 3) undo if payment is refused
  local moved, sum2 = {}, 0
  for _, id in ipairs(ids) do
    local n = inv.move(io_chest, stock_names, id, offer[id])
    if n > 0 then moved[id] = n; sum2 = sum2 + total(id, states, "sell", n) end
  end
  if sum2 < 1 then return ui:message("Failed", "Could not store the items.", "bad") end
  local ref = proto.rand_hex(10)
  local r = call({ type = "pay_out", to = acct, amount = sum2, memo = "Sold items", ref = ref }, 14, 3)
  if r and r.ok then
    for id, n in pairs(moved) do report(id, "sell", n) end
    ui:message("Paid!", { "+" .. money.short(sum2) .. " Cr", "sent to " .. l.name }, "ok")
  elseif r and r.err ~= "unknown" then
    for id, n in pairs(moved) do take_stock(id, n) end
    ui:message("Declined", r.err == "funds" and "Shop can't afford this right now." or reason(r), "bad")
  else
    note_pending("payout_unknown", ref, sum2, { to = acct })
    ui:message("Unsure", { "Payment status unknown.", "Ref " .. ref, "Ask the shop owner." }, "bad")
  end
end

---------------------------------------------------------------- main
local function main()
  while true do
    if not io_chest or #stock_names == 0 then
      ui:message("Out of order", "Chest or storage missing.", "bad", 10)
    else
      local menu = {}
      if mode ~= "buy" then menu[#menu + 1] = { id = "buy", label = "Buy items" } end
      if mode ~= "sell" then menu[#menu + 1] = { id = "sell", label = "Sell items", bg = colors.orange } end
      local id = ui:menu(cfg.name, menu, { sub = mismatch and "PRICE FILE OLD!" or "Live prices" })
      if id == "buy" then player_buy() elseif id == "sell" then player_sell() end
    end
  end
end

while true do
  local ok, err = pcall(main)
  if not ok then
    if tostring(err):find("Terminated") then break end
    printError("Shop error: " .. tostring(err))
    pcall(function() ui:message("Out of order", "Restarting...", "bad", 5) end)
  end
end
