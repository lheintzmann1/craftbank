-- BANK SERVER. Run on a computer with a modem (ender modem recommended). Terminal = admin console.
local dir = fs.getDir(fs.getDir(shell.getRunningProgram()))
package.path = "/" .. dir .. "/?.lua;" .. package.path

local cfg    = require("bank.config")
local store  = require("common.storage")
local serial = require("common.serial")
local proto  = require("common.protocol")
local proc   = require("common.proc")
local money  = require("common.money")
local webhook = require("common.webhook")
local Bank   = require("bank.core")

for _, side in ipairs(redstone.getSides()) do
  if peripheral.getType(side) == "modem" then rednet.open(side) end
end
if not rednet.isOpen() then error("No modem attached") end

local datadir = cfg.data_dir or "/bankdata"
fs.makeDir(datadir)
local db = store.open(datadir .. "/accounts.db")

local exch = proto.client({ dev = "bank:" .. cfg.number, key = cfg.exchange_key, host = "exchange", fixed = cfg.exchange_computer })

-- Webhook notification helper
local function notify_webhook(event, data)
  if not cfg.discord_webhook then return end
  local ok, err = pcall(function()
    if event == "transfer" then
      local threshold = cfg.discord_big_transfer_threshold or 100000
      if data.amount >= threshold then
        webhook.notify_transfer(cfg.discord_webhook, data.from, data.to, data.amount, data.fee, cfg.name)
      end
    elseif event == "pending" and cfg.discord_notify_pending then
      webhook.notify_alert(cfg.discord_webhook, "pending", data.message, cfg.number, cfg.name)
    elseif event == "limit" and cfg.discord_notify_limits then
      webhook.notify_alert(cfg.discord_webhook, "limit", data.message, cfg.number, cfg.name)
    end
  end)
end

local bank = Bank.new({
  number = cfg.number, name = cfg.name, db = db.data, save = db.save, clock = proto.now, fees = cfg.fees,
  rand_hex = proto.rand_hex, rand_int = proto.rand_int,
  log = function(e) store.append(datadir .. "/ledger.log", serial.encode(e)) end,
  net = {
    route = function(dest, op, args)
      return exch:call({ type = "route", dest = dest, op = op, args = args }, 10, op == "credit" and 2 or 1)
    end,
    market = function(op, args) return exch:call({ type = "market", op = op, args = args }, 6, 1) end,
  },
})

local function keyfn(devid)
  if devid == "exchange" then return cfg.exchange_key end
  local d = db.data.devices[devid]
  return d and d.key
end

---------------------------------------------------------------- admin console
local function cli()
  term.clear(); term.setCursorPos(1, 1)
  print(cfg.name .. " (bank " .. cfg.number .. ") online. Type 'help'.")
  local function acct(n) return db.data.accounts[tostring(n):gsub("^%d%d%-", "")] end
  while true do
    write("> ")
    local line = read() or ""
    local a = {}
    for w in line:gmatch("%S+") do a[#a + 1] = w end
    local cmd, sub = a[1], a[2]
    if cmd == "help" then
      print("status | dev add <atm|shop> <id> [acct6] [limit_Cr] | dev list | dev del <id> | dev off|on <id>")
      print("acct list | acct info <n> | acct freeze|unfreeze <n> | house pay <BB-NNNNNN> <Cr>")
      print("pending | pending refund|drop <txid>")
    elseif cmd == "status" then
      local n = 0; for _ in pairs(db.data.accounts) do n = n + 1 end
      print(n .. " accounts, deposits " .. money.fmtc(bank:total_deposits()) .. ", house " .. money.fmtc(bank:house().bal))
    elseif cmd == "dev" and sub == "add" then
      local limit = a[6] and money.parse(a[6])
      local key, err = bank:add_device(a[4], a[3], a[5], limit)
      if key then print("Device registered. Put this in its config:"); print("  device_id  = \"" .. a[4] .. "\""); print("  device_key = \"" .. key .. "\"")
      else printError("failed: " .. tostring(err)) end
    elseif cmd == "dev" and sub == "list" then
      for id, d in pairs(db.data.devices) do
        local st = d.status
        print(string.format("%-14s %-5s %s%s%s", id, d.type, d.acct and ("acct " .. d.acct .. " ") or "",
          d.disabled and "[OFF] " or "", st and ("vault=" .. tostring(st.vault) .. " seen " .. math.floor((proto.now() - st.t) / 1000) .. "s ago") or ""))
      end
    elseif cmd == "dev" and (sub == "del" or sub == "off" or sub == "on") and db.data.devices[a[3]] then
      if sub == "del" then db.data.devices[a[3]] = nil else db.data.devices[a[3]].disabled = (sub == "off") end
      db.save(); print("ok")
    elseif cmd == "acct" and sub == "list" then
      for n, ac in pairs(db.data.accounts) do print(bank:full(n), ac.owner, money.fmt(ac.bal), ac.frozen and "FROZEN" or "") end
    elseif cmd == "acct" and sub == "info" and acct(a[3]) then
      local ac = acct(a[3]); print(ac.owner, money.fmtc(ac.bal))
      for _, h in ipairs(ac.hist or {}) do print(" ", h.k, money.fmt(h.amt), h.memo or "") end
    elseif cmd == "acct" and (sub == "freeze" or sub == "unfreeze") and acct(a[3]) then
      acct(a[3]).frozen = (sub == "freeze"); db.save(); print("ok")
    elseif cmd == "house" and sub == "pay" then
      local amt = money.parse(a[4] or "")
      local r = amt and bank:pay(bank:house(), a[3], amt, "house payout", { kind = "admin" })
      print(r and (r.ok and "paid" or r.msg) or "usage: house pay <BB-NNNNNN> <Cr>")
    elseif cmd == "pending" and not sub then
      local any
      for txid, p in pairs(db.data.pending) do any = true; print(txid, "acct " .. p.acct, "->", p.to, money.fmt(p.amt)) end
      if not any then print("none") end
    elseif cmd == "pending" and (sub == "refund" or sub == "drop") then
      print(bank:resolve_pending(a[3] or "", sub) and "resolved" or "no such tx")
    elseif cmd and cmd ~= "" then print("unknown command, try 'help'") end
  end
end

---------------------------------------------------------------- go
proc.spawn(cli)
proc.spawn(function()
  proto.serve({
    hostname = "bank-" .. cfg.number, label = "bank", keyfn = keyfn, spawn = proc.spawn,
    handle = function(devid, msg)
      local r = bank:handle(devid, msg)
      -- Notify Discord for various events
      if cfg.discord_webhook then
        local ok, err = pcall(function()
          if msg.type == "transfer" and r and r.ok and msg.amount >= (cfg.discord_big_transfer_threshold or 100000) then
            -- Extract from account from token if we can
            local from_acct = "Unknown"
            if msg.tok then
              for tok, session in pairs(bank.sessions) do
                if tok == msg.tok then
                  from_acct = bank:full(session.acct)
                  break
                end
              end
            end
            webhook.notify_transfer(cfg.discord_webhook, from_acct, msg.to or "Unknown", msg.amount, 0, cfg.name)
          elseif msg.type == "deposit" and r and r.ok and cfg.discord_notify_pending then
            webhook.notify_alert(cfg.discord_webhook, "deposit", "Large deposit: " .. money.fmt(msg.amount or 0) .. " Cr", cfg.number, cfg.name)
          elseif msg.type == "withdraw" and r and r.ok and cfg.discord_notify_pending then
            webhook.notify_alert(cfg.discord_webhook, "withdraw", "Large withdrawal: " .. money.fmt(msg.amount or 0) .. " Cr", cfg.number, cfg.name)
          end
        end)
      end
      return r
    end,
  })
end)
proc.run()
