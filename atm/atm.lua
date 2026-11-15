-- ATM: touch UI on a 1x1 monitor, ONE chest for deposit+withdraw, vault storage behind the wall.
local dir = fs.getDir(fs.getDir(shell.getRunningProgram()))
package.path = "/" .. dir .. "/?.lua;" .. package.path

local cfg   = require("atm.config")
local const = require("common.const")
local money = require("common.money")
local proto = require("common.protocol")
local store = require("common.storage")
local UI    = require("common.ui")
local inv   = require("common.inventory")

local DIAMOND = "minecraft:diamond"

---------------------------------------------------------------- hardware
for _, side in ipairs(redstone.getSides()) do
  if peripheral.getType(side) == "modem" then rednet.open(side) end
end
local mon = cfg.monitor and peripheral.wrap(cfg.monitor) or peripheral.find("monitor")
if not mon then error("No monitor found") end
mon.setTextScale(cfg.text_scale or 0.5)
local ui = UI.new(mon, cfg.monitor or peripheral.getName(mon))

local chest = cfg.io_chest or inv.names("chest")[1]
local vault = cfg.vault or inv.names("barrel")
-- Ensure vault is always a table (array)
if type(vault) == "string" then vault = { vault } end
local function hw_error()
  if not chest then return "No chest on the network" end
  if #vault == 0 then return "No vault storage" end
end

local link = proto.client({ dev = cfg.device_id, key = cfg.device_key, host = "bank-" .. cfg.bank_no, fixed = cfg.bank_computer })
local function call(msg, tries) return link:call(msg, 6, tries or 1) end

local S                       -- current session { tok, acct, owner, bal }
local PENDING = (fs.getDir(shell.getRunningProgram()) .. "/pending.log")

local function note_pending(kind, ref, amount)
  store.append(PENDING, textutils.serialise({ t = proto.now(), kind = kind, ref = ref, amount = amount, who = S and S.acct }, { compact = true }))
end

local function fmt_acct(s) return #s > 2 and (s:sub(1, 2) .. "-" .. s:sub(3)) or s end
local function reason(r) if not r then return "Bank unreachable. Try later." end; return r.msg or r.err or "Error" end

---------------------------------------------------------------- vault helpers
local function vault_count() return inv.count(vault, DIAMOND) + 9 * inv.count(vault, "minecraft:diamond_block") end

local function take_from_vault(id, qty)
  local left = qty
  for _, v in ipairs(vault) do
    if left <= 0 then break end
    left = left - inv.move(v, { chest }, id, left)
  end
  return qty - left
end

---------------------------------------------------------------- session actions
local function logout()
  if S then call({ type = "logout", tok = S.tok }); S = nil end
end

local function login()
  local acct = ui:keypad("Account no.", { maxlen = 8, minlen = 8, hint = "BB-NNNNNN", fmt = fmt_acct, timeout = 60 })
  if not acct then return end
  local pin = ui:keypad("PIN", { maxlen = 4, minlen = 4, masked = true, timeout = 60 })
  if not pin then return end
  ui:splash("Login")
  local r = call({ type = "login", acct = acct, pin = pin })
  if r and r.ok then S = { tok = r.tok, acct = r.acct, owner = r.owner, bal = r.bal }; return true end
  ui:message("Denied", reason(r), "bad")
end

local function do_deposit()
  if not ui:confirm("Deposit", "Put diamonds in the chest, then tap OK", "OK", "Cancel") then return end
  ui:splash("Deposit", "Counting...")
  local moved = inv.move_where(chest, vault, function(st) return cfg.accept[st.name] and not st.nbt end)
  local value, diamonds = 0, 0
  for id, c in pairs(moved) do
    diamonds = diamonds + c * cfg.accept[id]
    value = value + c * cfg.accept[id] * const.DIAMOND
  end
  if value == 0 then
    return ui:message("Nothing found", "Only diamonds and diamond blocks are accepted.", "bad")
  end
  local ref = proto.rand_hex(10)
  local r = call({ type = "deposit", tok = S.tok, amount = value, ref = ref }, 3)
  if r and r.ok then
    S.bal = r.bal
    ui:message("Deposited", { diamonds .. " diamonds", "+" .. money.short(value) .. " Cr", "Balance " .. money.short(S.bal) }, "ok")
  elseif r then
    for id, c in pairs(moved) do                       -- bank said no: give the items back
      local left = c
      for _, v in ipairs(vault) do if left > 0 then left = left - inv.move(v, { chest }, id, left) end end
    end
    ui:message("Refused", reason(r) .. " Items returned.", "bad")
  else
    note_pending("deposit", ref, value)                -- unknown outcome: never guess, keep items, tell the player
    ui:message("Network error", { "Deposit recorded.", "Ref " .. ref, "Contact your bank if the balance is not updated." }, "bad")
  end
end

local function do_withdraw()
  local stock = inv.count(vault, DIAMOND)
  local room = inv.free_space(chest, DIAMOND)
  local maxn = math.min(stock, room, math.floor(S.bal / const.DIAMOND))
  if maxn < 1 then
    local why = stock < 1 and "ATM is out of diamonds." or room < 1 and "Empty the chest first." or "Not enough funds (1 diamond = 1,000 Cr)."
    return ui:message("Withdraw", why, "bad")
  end
  local s = ui:keypad("Diamonds", { maxlen = 4, hint = "max " .. maxn, timeout = 60 })
  local n = s and tonumber(s)
  if not n or n < 1 then return end
  if n > maxn then return ui:message("Too many", "Maximum right now: " .. maxn, "bad") end
  local amount = n * const.DIAMOND
  if not ui:confirm("Withdraw", { n .. " diamonds", "= " .. money.short(amount) .. " Cr" }, "OK", "Cancel") then return end
  ui:splash("Withdraw")
  local ref = proto.rand_hex(10)
  local r = call({ type = "withdraw", tok = S.tok, amount = amount, ref = ref }, 3)
  if r and r.ok then
    S.bal = r.bal
    local moved = take_from_vault(DIAMOND, n)
    if moved < n then
      local back = call({ type = "reverse", ref = ref, amount = (n - moved) * const.DIAMOND }, 3)
      if back and back.ok then S.bal = back.bal else note_pending("reverse", ref, (n - moved) * const.DIAMOND) end
      return ui:message("Partial", { "Only " .. moved .. " dispensed.", "The rest was refunded." }, "bad")
    end
    ui:message("Take your diamonds", { n .. " diamonds are in the chest.", "Balance " .. money.short(S.bal) }, "ok")
  elseif r then ui:message("Refused", reason(r), "bad")
  else
    note_pending("withdraw", ref, amount)
    ui:message("Network error", { "Nothing was dispensed.", "Ref " .. ref, "Ask your bank to check." }, "bad")
  end
end

local function do_transfer()
  local to = ui:keypad("To account", { maxlen = 8, minlen = 8, hint = "BB-NNNNNN", fmt = fmt_acct, timeout = 60 })
  if not to then return end
  ui:splash("Transfer", "Checking...")
  local l = call({ type = "lookup", acct = to }, 2)
  if not (l and l.ok) then return ui:message("Not found", reason(l), "bad") end
  local s = ui:keypad("Amount (Cr)", { maxlen = 9, hint = "bal " .. money.short(S.bal), timeout = 60 })
  local amt = s and tonumber(s) and tonumber(s) * const.SCALE
  if not amt or amt < 1 then return end
  if not ui:confirm("Send?", { money.short(amt) .. " Cr", "to " .. l.name, l.bank or "" }, "Send", "Cancel") then return end
  ui:splash("Transfer")
  local r = call({ type = "transfer", tok = S.tok, to = to, amount = amt, ref = proto.rand_hex(10) }, 3)
  if r and r.ok then
    S.bal = r.bal
    ui:message("Sent", { money.short(amt) .. " Cr", r.fee > 0 and ("fee " .. money.short(r.fee)) or "no fee", "Balance " .. money.short(S.bal) }, "ok")
  else ui:message("Failed", reason(r), "bad") end
end

local function do_code()
  local s = ui:keypad("Max to spend", { maxlen = 7, hint = "amount in Cr", timeout = 60 })
  local mx = s and tonumber(s) and tonumber(s) * const.SCALE
  if not mx or mx < 1 then return end
  ui:splash("Pay code")
  local r = call({ type = "gen_code", tok = S.tok, max = mx })
  if r and r.ok then
    ui:message("Pay code", { "Enter at a shop:", r.code:sub(1, 2) .. " " .. r.code:sub(3), "Valid 10 min", "Max " .. money.short(mx) .. " Cr" }, "ok", 90)
  else ui:message("Failed", reason(r), "bad") end
end

local KIND = { dep = "Deposit", wd = "Withdraw", xfer = "Sent", xfer_in = "Received", shop = "Shop", shop_in = "Sale",
  fee = "Fee", refund = "Refund", admin = "Bank" }
local function do_history()
  ui:splash("History")
  local r = call({ type = "history", tok = S.tok })
  if not (r and r.ok) then return ui:message("Failed", reason(r), "bad") end
  S.bal = r.bal
  local rows = {}
  for _, h in ipairs(r.hist) do
    rows[#rows + 1] = { l = KIND[h.k] or h.k, r = (h.amt >= 0 and "+" or "") .. money.short(h.amt), rfg = h.amt >= 0 and colors.lime or colors.red }
  end
  if #rows == 0 then rows[1] = { l = "No activity yet" } end
  ui:list("History", rows)
end

local function do_pin()
  local old = ui:keypad("Current PIN", { maxlen = 4, minlen = 4, masked = true }); if not old then return end
  local new = ui:keypad("New PIN", { maxlen = 4, minlen = 4, masked = true }); if not new then return end
  local again = ui:keypad("Repeat PIN", { maxlen = 4, minlen = 4, masked = true }); if not again then return end
  if again ~= new then return ui:message("Mismatch", "PINs differ.", "bad") end
  local r = call({ type = "change_pin", tok = S.tok, old = old, new = new })
  if r and r.ok then ui:message("PIN changed", "Done.", "ok") else ui:message("Failed", reason(r), "bad") end
end

local function more_menu()
  while S do
    local id = ui:menu("More", {
      { id = "hist", label = "History" }, { id = "code", label = "Pay code" },
      { id = "pin", label = "Change PIN" }, { id = "out", label = "Log out", bg = colors.red } },
      { back = true, timeout = cfg.idle_timeout or 45 })
    if id == "hist" then do_history() elseif id == "code" then do_code() elseif id == "pin" then do_pin()
    elseif id == "out" or id == nil then logout() else return end
  end
end

local function session()
  while S do
    local id = ui:menu(S.owner, {
      { id = "dep", label = "Deposit" }, { id = "wd", label = "Withdraw" },
      { id = "tr", label = "Transfer" }, { id = "more", label = "More..." } },
      { sub = "Bal " .. money.short(S.bal), timeout = cfg.idle_timeout or 45 })
    if id == "dep" then do_deposit() elseif id == "wd" then do_withdraw() elseif id == "tr" then do_transfer()
    elseif id == "more" then more_menu() elseif id == nil then logout() end
  end
end

local function new_account()
  local name = ui:keyboard("Your name", { maxlen = 16 }); if not name then return end
  local pin = ui:keypad("Choose PIN", { maxlen = 4, minlen = 4, masked = true }); if not pin then return end
  local again = ui:keypad("Repeat PIN", { maxlen = 4, minlen = 4, masked = true }); if not again then return end
  if again ~= pin then return ui:message("Mismatch", "PINs differ.", "bad") end
  ui:splash("Opening account")
  local r = call({ type = "open", owner = name, pin = pin })
  if r and r.ok then
    ui:message("Welcome " .. r.owner, { "Your account number:", r.acct, "WRITE IT DOWN!" }, "ok", 120)
  else ui:message("Failed", reason(r), "bad") end
end

local function report_status()
  call({ type = "status", vault = vault_count(), info = hw_error() or "ok" })
end

---------------------------------------------------------------- main loop
local function main()
  report_status()
  while true do
    local bad = hw_error()
    if bad then ui:message("Out of order", bad, "bad", 10)
    else
      local items = { { id = "login", label = "Log in" } }
      if cfg.allow_open_account ~= false then items[2] = { id = "new", label = "New account" } end
      local id = ui:menu(cfg.short_name or "Bank", items, { sub = "Welcome", timeout = 60 })
      if id == "login" then if login() then session() end
      elseif id == "new" then new_account()
      elseif id == nil then report_status() end
    end
  end
end

while true do
  local ok, err = pcall(main)
  if not ok then
    if tostring(err):find("Terminated") then break end
    S = nil
    printError("ATM error: " .. tostring(err))
    pcall(function() ui:message("Out of order", "Restarting...", "bad", 5) end)
  end
end
