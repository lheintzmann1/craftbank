-- Run the real ATM and shop programs headless against real bank + exchange cores.
local mock = dofile("tests/cc_mock.lua")
local Bank = require("bank.core")
local Exchange = require("exchange.core")
local proto = require("common.protocol")
local items = require("common.items")
local DIA = 100000
local clock = function() return os.epoch("utc") end

mock.install(); mock.capture_ui()
package.loaded["common.storage"] = { append = function() end }

local ex = Exchange.new({ db = {}, clock = clock, rand = math.random, cfg = {},
  deliver = function(no, msg) return nil end })
ex:add_bank(1, "Royal", "k")
local bank = Bank.new({ number = 1, name = "Royal", db = {}, clock = clock, pin_rounds = 2,
  rand_hex = proto.rand_hex, rand_int = proto.rand_int, fees = {},
  net = { market = function(op, args) return ex:handle(1, { type = "market", op = op, args = args }) end } })

-- every client created by the programs talks to the in-process bank
package.loaded["common.protocol"].client = function(o)
  return { call = function(_, msg) local r = bank:handle(o.dev, msg); r.rid = msg.rid; return r end }
end

local atm_key = bank:add_device("ATM-T", "atm")
local function run(program, cfg_name, cfg, actions)
  package.loaded[cfg_name] = cfg
  mock.program, mock.actions = program, actions
  local ok, err = pcall(dofile, program)
  assert(ok, err)
  assert(#mock.actions == 0, "unused actions: " .. #mock.actions)
end
local function keys(s) local t = {}; for c in s:gmatch(".") do t[#t + 1] = c end; return t end
local function cat(...) local r = {}; for _, t in ipairs({ ... }) do for _, v in ipairs(t) do r[#r + 1] = v end end; return r end

local chest = mock.inventory("minecraft:chest_0", 27)
local vault = mock.inventory("minecraft:barrel_0", 27)
local acct

test("ATM: open account via on-screen keyboard", function()
  run("atm/atm.lua", "atm.config", { device_id = "ATM-T", device_key = atm_key, bank_no = 1, short_name = "Royal",
    accept = { ["minecraft:diamond"] = 1, ["minecraft:diamond_block"] = 9 } },
    cat({ "new" }, keys("ZED"), { "_ok" }, keys("1234"), { "OK" }, keys("1234"), { "OK" }, { "x" }))
  for n, a in pairs(bank.db.accounts) do if a.owner == "Zed" then acct = bank:full(n) end end
  truthy(acct, "account was created with auto-capitalised name 'Zed'")
end)

test("ATM: deposit via single chest, vault fills, balance credited", function()
  chest:add("minecraft:diamond", 5); chest:add("minecraft:dirt", 3)
  run("atm/atm.lua", "atm.config", { device_id = "ATM-T", device_key = atm_key, bank_no = 1,
    accept = { ["minecraft:diamond"] = 1, ["minecraft:diamond_block"] = 9 } },
    cat({ "login" }, keys(acct:gsub("-", "")), { "OK" }, keys("1234"), { "OK" }, { "dep", "yes", "x", "more", "out" }))
  eq(bank.db.accounts[acct:sub(4)].bal, 5 * DIA)
  eq(vault:total("minecraft:diamond"), 5); eq(chest:total("minecraft:diamond"), 0)
  eq(chest:total("minecraft:dirt"), 3, "non-accepted items stay in the chest")
end)

test("ATM: withdraw 2 diamonds from the vault into the same chest", function()
  run("atm/atm.lua", "atm.config", { device_id = "ATM-T", device_key = atm_key, bank_no = 1 },
    cat({ "login" }, keys(acct:gsub("-", "")), { "OK" }, keys("1234"), { "OK" }, { "wd" }, keys("2"), { "OK", "yes", "x", "more", "out" }))
  eq(bank.db.accounts[acct:sub(4)].bal, 3 * DIA)
  eq(chest:total("minecraft:diamond"), 2); eq(vault:total("minecraft:diamond"), 3)
end)

test("ATM: wrong PIN is refused; withdraw above balance is blocked", function()
  run("atm/atm.lua", "atm.config", { device_id = "ATM-T", device_key = atm_key, bank_no = 1 },
    cat({ "login" }, keys(acct:gsub("-", "")), { "OK" }, keys("9999"), { "OK", "x" }))
  local before = bank.db.accounts[acct:sub(4)].bal
  run("atm/atm.lua", "atm.config", { device_id = "ATM-T", device_key = atm_key, bank_no = 1 },
    cat({ "login" }, keys(acct:gsub("-", "")), { "OK" }, keys("1234"), { "OK" }, { "wd" }, keys("9"), { "OK", "x", "more", "out" }))
  eq(bank.db.accounts[acct:sub(4)].bal, before)
end)

test("ATM: pay code, history and idle timeout logout", function()
  run("atm/atm.lua", "atm.config", { device_id = "ATM-T", device_key = atm_key, bank_no = 1 },
    cat({ "login" }, keys(acct:gsub("-", "")), { "OK" }, keys("1234"), { "OK" }, { "more", "code" }, keys("2000"), { "OK", "x", "hist", "back", "out" }))
  local n = 0; for _ in pairs(bank.codes) do n = n + 1 end; eq(n, 1)
  run("atm/atm.lua", "atm.config", { device_id = "ATM-T", device_key = atm_key, bank_no = 1 },
    cat({ "login" }, keys(acct:gsub("-", "")), { "OK" }, keys("1234"), { "OK" }, { "timeout" }))
  local live = 0; for _ in pairs(bank.sessions) do live = live + 1 end
  eq(live, 0, "idle timeout logs out")
end)

test("SHOP: player buys iron with a pay code; stock moves; market price reacts", function()
  -- shop owner account + shop device
  local owner = bank:handle("ATM-T", { type = "open", owner = "Shopkeep", pin = "5555" }).acct
  local skey = bank:add_device("SHOP-T", "shop", owner:sub(4))
  local stock = mock.inventory("minecraft:barrel_1", 27)
  stock:add("minecraft:iron_ingot", 100)
  chest.slots = {}
  -- customer logs in directly at the bank to make a code (as the ATM would)
  local tok = bank:handle("ATM-T", { type = "login", acct = acct, pin = "1234" }).tok
  local code = bank:handle("ATM-T", { type = "gen_code", tok = tok, max = 5000 * 100 }).code
  local id = "minecraft:iron_ingot"
  run("shop/shop.lua", "shop.config", { device_id = "SHOP-T", device_key = skey, bank_no = 1, name = "T Shop", mode = "both",
      overrides = {} },
    cat({ "buy", id, 10, -1 }, { "ok" }, keys(code), { "OK", "x", "back" }))
  eq(chest:total(id), 10, "customer got 10 ingots in the chest")
  local paid = bank.db.accounts[owner:sub(4)].bal
  truthy(paid > 10 * 3900 and paid < 10 * 4200, "paid about 10 x 40 Cr, got " .. paid)
  truthy(ex:flow(id, clock()) >= 9.9, "trade reported to the market")
end)

test("SHOP: player sells items; shop pays them; unaffordable offers are refunded", function()
  local id = "minecraft:coal"
  chest.slots = {}; chest:add(id, 64)
  local owner_n; for n, a in pairs(bank.db.accounts) do if a.owner == "Shopkeep" then owner_n = n end end
  bank.db.accounts[owner_n].bal = 10 * DIA        -- the shop owner has working capital
  local before_player = bank.db.accounts[acct:sub(4)].bal
  local skey = bank.db.devices["SHOP-T"].key
  run("shop/shop.lua", "shop.config", { device_id = "SHOP-T", device_key = skey, bank_no = 1, name = "T Shop", mode = "both" },
    cat({ "sell", "yes", "back", "yes" }, keys(acct:gsub("-", "")), { "OK", "yes", "x" }))
  truthy(bank.db.accounts[acct:sub(4)].bal > before_player, "player was paid")
  eq(chest:total(id), 0, "items left the chest")
  -- now a shop owner with an empty account cannot pay: items must return to the chest
  bank.db.accounts[owner_n].bal = 0
  chest:add(id, 64)
  run("shop/shop.lua", "shop.config", { device_id = "SHOP-T", device_key = skey, bank_no = 1, name = "T Shop", mode = "both" },
    cat({ "sell", "yes", "back", "yes" }, keys(acct:gsub("-", "")), { "OK", "yes", "x" }))
  eq(chest:total(id), 64, "refused payment -> items handed back")
end)
