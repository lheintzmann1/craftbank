-- Integration: two banks + one exchange wired together in-process.
local Bank = require("bank.core")
local Exchange = require("exchange.core")
local proto = require("common.protocol")
local items = require("common.items")

local DIA = 100000
local now = 1000000
local clock = function() return now end

local function make_world(opts)
  opts = opts or {}
  local w = { banks = {}, down = {} }
  w.ex = Exchange.new({ db = {}, clock = clock, rand = math.random, cfg = { default_limit = 5 * DIA },
    deliver = function(no, msg)
      if w.down[no] then return nil end
      return w.banks[no]:handle("exchange", msg)
    end })
  for no, name in pairs({ [1] = "Royal", [2] = "Merchant" }) do
    w.ex:add_bank(no, name, "key" .. no)
    w.banks[no] = Bank.new({ number = no, name = name, db = {}, clock = clock, pin_rounds = 2,
      rand_hex = proto.rand_hex, rand_int = proto.rand_int,
      fees = { interbank_flat = 500, transfer_pct = 0, max_accounts_per_owner = 2 },
      net = {
        route = function(dest, op, args)
          if w.drop_replies then return nil end
          return w.ex:handle(no, { type = "route", dest = dest, op = op, args = args })
        end,
        market = function(op, args) return w.ex:handle(no, { type = "market", op = op, args = args }) end,
      } })
  end
  return w
end

local function open(w, no, owner, pin)
  local b = w.banks[no]
  if not b.db.devices["ATM"] then b:add_device("ATM", "atm") end
  local r = b:handle("ATM", { type = "open", owner = owner, pin = pin })
  assert(r.ok, r.msg)
  local l = b:handle("ATM", { type = "login", acct = r.acct, pin = pin })
  assert(l.ok, l.msg)
  return r.acct, l.tok
end

local function deposit(w, no, tok, amt)
  return w.banks[no]:handle("ATM", { type = "deposit", tok = tok, amount = amt, ref = proto.rand_hex(8) })
end

test("open, login, deposit, withdraw, idempotent retry", function()
  local w = make_world(); local b = w.banks[1]
  local acct, tok = open(w, 1, "Steve", "1234")
  truthy(acct:match("^01%-%d%d%d%d%d%d$"))
  eq(deposit(w, 1, tok, 3 * DIA).bal, 3 * DIA)
  local ref = "r1"
  local r1 = b:handle("ATM", { type = "withdraw", tok = tok, amount = DIA, ref = ref })
  local r2 = b:handle("ATM", { type = "withdraw", tok = tok, amount = DIA, ref = ref })   -- retry, same ref
  eq(r1.bal, 2 * DIA); eq(r2.bal, 2 * DIA)
  local acc = b.db.accounts[acct:sub(4)]; eq(acc.bal, 2 * DIA, "retry must not double-debit")
  eq(b:handle("ATM", { type = "withdraw", tok = tok, amount = 9 * DIA, ref = "r2" }).err, "funds")
end)

test("wrong PIN lockout, tokens bound to device", function()
  local w = make_world(); local b = w.banks[1]
  local acct = open(w, 1, "Alex", "4321")
  for _ = 1, 3 do eq(b:handle("ATM", { type = "login", acct = acct, pin = "0000" }).err, "auth") end
  eq(b:handle("ATM", { type = "login", acct = acct, pin = "4321" }).err, "locked")
  now = now + 301000
  local l = b:handle("ATM", { type = "login", acct = acct, pin = "4321" }); truthy(l.ok)
  b:add_device("ATM2", "atm")
  eq(b:handle("ATM2", { type = "history", tok = l.tok }).err, "session", "token from another device")
  now = now + 130000
  eq(b:handle("ATM", { type = "history", tok = l.tok }).err, "session", "expired")
end)

test("unknown/disabled/wrong-role devices are refused", function()
  local w = make_world(); local b = w.banks[1]
  eq(b:handle("ghost", { type = "login" }).err, "denied")
  b:add_device("ATM", "atm")
  eq(b:handle("ATM", { type = "pay_out", to = "01-123456", amount = 1 }).err, "denied")
  eq(b:handle("ATM", { type = "x_credit" }).err, "denied")
end)

test("local transfer with percentage fee goes to the house", function()
  local w = make_world(); local b = w.banks[1]; b.fees.transfer_pct = 0.01
  local a1, t1 = open(w, 1, "Anna", "1111"); local a2 = open(w, 1, "Bob", "2222")
  deposit(w, 1, t1, DIA)
  local r = b:handle("ATM", { type = "transfer", tok = t1, to = a2, amount = 50000, ref = "t1" })
  truthy(r.ok, r.msg); eq(r.fee, 500)
  eq(b.db.accounts[a1:sub(4)].bal, DIA - 50000 - 500)
  eq(b.db.accounts[a2:sub(4)].bal, 50000)
  eq(b:house().bal, 500)
  eq(b:handle("ATM", { type = "transfer", tok = t1, to = a1, amount = 1, ref = "t2" }).err, "bad_request", "self transfer")
  eq(b:handle("ATM", { type = "transfer", tok = t1, to = "01-999999", amount = 1, ref = "t3" }).err, "no_account")
end)

test("interbank transfer: fee, positions, money conserved", function()
  local w = make_world(); local b1, b2 = w.banks[1], w.banks[2]
  local a1, t1 = open(w, 1, "Anna", "1111"); local a2 = open(w, 2, "Bob", "2222")
  deposit(w, 1, t1, 2 * DIA)
  local r = b1:handle("ATM", { type = "transfer", tok = t1, to = a2, amount = DIA, ref = "x1" })
  truthy(r.ok, r.msg); eq(r.fee, 500)
  eq(b1.db.accounts[a1:sub(4)].bal, 2 * DIA - DIA - 500)
  eq(b2.db.accounts[a2:sub(4)].bal, DIA)
  eq(w.ex.db.pos[1], -DIA); eq(w.ex.db.pos[2], DIA)
  -- lookup across banks shows masked owner
  local l = b1:handle("ATM", { type = "lookup", acct = a2 }); eq(l.name, "Bob")
  eq(b1:handle("ATM", { type = "lookup", acct = "02-000000" }).err, "no_account")
end)

test("interbank: unknown account refunds, credit limit enforced", function()
  local w = make_world(); local b1 = w.banks[1]
  local a1, t1 = open(w, 1, "Anna", "1111")
  deposit(w, 1, t1, 20 * DIA)
  local r = b1:handle("ATM", { type = "transfer", tok = t1, to = "02-555555", amount = DIA, ref = "y1" })
  eq(r.ok, false); eq(r.err, "no_account")
  eq(b1.db.accounts[a1:sub(4)].bal, 20 * DIA, "refunded in full (incl. fee)")
  eq(next(b1.db.pending), nil, "nothing pending")
  local a2 = open(w, 2, "Bob", "2222")
  local ok = 0
  for i = 1, 8 do
    local rr = b1:handle("ATM", { type = "transfer", tok = t1, to = a2, amount = DIA, ref = "z" .. i })
    if rr.ok then ok = ok + 1 else eq(rr.err, "limit") end
  end
  eq(ok, 5, "limit of 5 diamonds net debt")
end)

test("interbank: destination offline -> pending, never refunded blindly", function()
  local w = make_world(); local b1 = w.banks[1]
  local a1, t1 = open(w, 1, "Anna", "1111"); local a2 = open(w, 2, "Bob", "2222")
  deposit(w, 1, t1, 2 * DIA)
  w.down[2] = true
  local r = b1:handle("ATM", { type = "transfer", tok = t1, to = a2, amount = DIA, ref = "p1" })
  eq(r.err, "unknown")
  local txid = r.txid; truthy(b1.db.pending[txid])
  eq(b1.db.accounts[a1:sub(4)].bal, 2 * DIA - DIA - 500)
  -- retry with same ref returns same answer, no double debit
  eq(b1:handle("ATM", { type = "transfer", tok = t1, to = a2, amount = DIA, ref = "p1" }).err, "unknown")
  eq(b1.db.accounts[a1:sub(4)].bal, 2 * DIA - DIA - 500)
  truthy(b1:resolve_pending(txid, "refund"))
  eq(b1.db.accounts[a1:sub(4)].bal, 2 * DIA)
end)

test("x_credit is idempotent by txid", function()
  local w = make_world(); local b2 = w.banks[2]
  local a2 = open(w, 2, "Bob", "2222")
  local msg = { type = "x_credit", to = a2:sub(4), amount = 1000, txid = "tx-1", from = "01-111111" }
  truthy(b2:handle("exchange", msg).ok); truthy(b2:handle("exchange", msg).ok)
  eq(b2.db.accounts[a2:sub(4)].bal, 1000)
end)

test("pay codes: shop charges customer without PIN, single use, cross-bank", function()
  local w = make_world(); local b1, b2 = w.banks[1], w.banks[2]
  local cust, ct = open(w, 1, "Carol", "1212"); deposit(w, 1, ct, 3 * DIA)
  local owner = open(w, 2, "ShopOwner", "9999")
  local shopkey = b2:add_device("SHOP-A", "shop", owner:sub(4)); truthy(shopkey)
  local g = b1:handle("ATM", { type = "gen_code", tok = ct, max = 2 * DIA })
  truthy(g.ok); truthy(g.code:match("^01%d%d%d%d%d%d$"))
  eq(b2:handle("SHOP-A", { type = "redeem", code = g.code, amount = 3 * DIA, ref = "s0" }).err, "limit")
  local r = b2:handle("SHOP-A", { type = "redeem", code = g.code, amount = 1500 * 100, ref = "s1" })
  truthy(r.ok, r.msg); eq(r.bal, nil, "shop must not learn customer balance")
  eq(b2.db.accounts[owner:sub(4)].bal, 150000)
  eq(b1.db.accounts[cust:sub(4)].bal, 3 * DIA - 150000)
  eq(b2:handle("SHOP-A", { type = "redeem", code = g.code, amount = 100, ref = "s2" }).err, "code", "code is single use")
  -- expiry
  local g2 = b1:handle("ATM", { type = "gen_code", tok = ct, max = DIA })
  now = now + 700000
  eq(b2:handle("SHOP-A", { type = "redeem", code = g2.code, amount = 100, ref = "s3" }).err, "code")
end)

test("pay code brute-force throttling", function()
  local w = make_world(); local b = w.banks[1]
  local owner = open(w, 1, "Own", "1234"); b:add_device("S", "shop", owner:sub(4))
  local last
  for i = 1, 12 do last = b:handle("S", { type = "redeem", code = string.format("01%06d", i), amount = 100, ref = "b" .. i }) end
  eq(last.err, "throttle")
end)

test("shop pay_out (buying items from a player) with limit", function()
  local w = make_world(); local b = w.banks[1]
  local oa, ot = open(w, 1, "Own", "1234"); deposit(w, 1, ot, 5 * DIA)
  local pa = open(w, 1, "Player", "4444")
  b:add_device("S", "shop", oa:sub(4), 2 * DIA)
  local r = b:handle("S", { type = "pay_out", to = pa, amount = DIA, ref = "po1" }); truthy(r.ok, r.msg)
  eq(b:handle("S", { type = "pay_out", to = pa, amount = 3 * DIA, ref = "po2" }).err, "limit")
  eq(b.db.accounts[pa:sub(4)].bal, DIA)
end)

test("withdraw reverse (partial dispense) and fee refund", function()
  local w = make_world(); local b = w.banks[1]; b.fees.withdraw_pct = 0.01
  local a, t = open(w, 1, "Wes", "1234"); deposit(w, 1, t, 10 * DIA)
  local acc = b.db.accounts[a:sub(4)]
  local r = b:handle("ATM", { type = "withdraw", tok = t, amount = 4 * DIA, ref = "w1" }); eq(r.fee, 4000)
  eq(acc.bal, 10 * DIA - 4 * DIA - 4000)
  truthy(b:handle("ATM", { type = "reverse", ref = "w1", amount = DIA }).ok)
  eq(acc.bal, 10 * DIA - 3 * DIA - 4000)
  truthy(b:handle("ATM", { type = "reverse", ref = "w1" }).ok)           -- the rest
  eq(acc.bal, 10 * DIA, "fully reversed incl. fee")
  eq(b:handle("ATM", { type = "reverse", ref = "w1" }).err, "bad_request", "nothing left to reverse")
end)

test("market ops through the bank: prices + trade impact", function()
  local w = make_world(); local b = w.banks[1]
  local oa = open(w, 1, "Own", "1234"); b:add_device("S", "shop", oa:sub(4))
  local id = "minecraft:iron_ingot"
  local p0 = b:handle("S", { type = "market", op = "prices", args = { items = { id } } })
  eq(p0.items[id][1], 0); eq(p0.digest, items.digest)
  truthy(b:handle("S", { type = "market", op = "report", args = { item = id, side = "buy", qty = 500 } }).ok)
  local p1 = b:handle("S", { type = "market", op = "prices", args = { items = { id } } })
  truthy(p1.items[id][1] > 400, "net flow rises after buys")
  eq(b:handle("S", { type = "market", op = "report", args = { item = id, side = "x", qty = 1 } }).err, "bad_request")
end)

test("server stats nudge prices; events apply; diamond is immune", function()
  local w = make_world(); local ex = w.ex
  local ore = "minecraft:iron_ingot"
  ex:apply_stats({ mined = { [ore] = 1000 } }, now)                        -- baseline, no effect
  eq(ex:flow(ore, now), 0)
  ex:apply_stats({ mined = { [ore] = 3000 }, used = { ["minecraft:diamond"] = 5 } }, now)
  truthy(ex:flow(ore, now) < 0, "mining adds supply -> price falls")
  local p = ex:mid(ore, now)
  ex:add_event(nil, "ore", 1.5, 10, "test", now)
  truthy(ex:mid(ore, now) > p * 1.4)
  eq(ex:mid("minecraft:diamond", now), 100000)
  now = now + 11 * 60000; ex:tick(now); eq(#ex.db.events <= 1, true)
end)

test("accounts: owner limit, bad PIN format, history", function()
  local w = make_world(); local b = w.banks[1]; b:add_device("ATM", "atm")
  eq(b:handle("ATM", { type = "open", owner = "Zed", pin = "12" }).ok, false)
  truthy(b:handle("ATM", { type = "open", owner = "Zed", pin = "1234" }).ok)
  truthy(b:handle("ATM", { type = "open", owner = "zed", pin = "1234" }).ok)
  eq(b:handle("ATM", { type = "open", owner = "ZED", pin = "1234" }).err, "exists")
end)
