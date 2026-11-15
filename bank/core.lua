-- BANK CORE: accounts, sessions, deposits/withdrawals, transfers, pay codes, interbank payments.
-- Pure logic: no rednet, no files. The server injects: db, save(), clock(), net, log(), rand_hex(), rand_int().
--
-- Account id format: "BB-NNNNNN" (BB = bank number, NNNNNN = 6 random digits)
-- Pay code format:   "BBCCCCCC"  (8 digits; BB = issuing bank)  -> lets shops charge you without ever seeing your PIN
local sha = require("common.sha256")

local Bank = {}
Bank.__index = Bank

local SESSION_MS = 120000
local CODE_MS    = 600000
local MAX_AMOUNT = 1e12

local ERR = {
  funds = "Insufficient funds", auth = "Wrong account or PIN", locked = "Too many tries. Wait 5 min",
  frozen = "Account frozen", no_account = "Account not found", bad_request = "Invalid request",
  session = "Session expired", denied = "Not allowed", limit = "Amount over limit",
  code = "Invalid or expired code", net = "Network error", unknown = "Outcome unknown. Ask your bank",
  exists = "Too many accounts", throttle = "Too many bad codes. Wait",
}
local function fail(err, extra)
  local r = { ok = false, err = err, msg = ERR[err] or err }
  if extra then for k, v in pairs(extra) do r[k] = v end end
  return r
end

local function valid_amt(a) return type(a) == "number" and a == math.floor(a) and a > 0 and a <= MAX_AMOUNT end
local function parse_full(s)
  local b, n = tostring(s or ""):match("^(%d%d)%-?(%d%d%d%d%d%d)$")
  if b then return tonumber(b), n end
end
Bank.parse_full = parse_full

---------------------------------------------------------------- construction
function Bank.new(o)
  local self = setmetatable({}, Bank)
  self.no, self.name = o.number, o.name or ("Bank " .. o.number)
  self.db, self.clock = o.db, o.clock
  self.save = o.save or function() end
  self.log = o.log or function() end
  self.net = o.net or {}
  self.fees = o.fees or {}
  self.rand_hex, self.rand_int = o.rand_hex, o.rand_int
  self.pin_rounds = o.pin_rounds or 64
  local db = self.db
  db.accounts = db.accounts or {}; db.devices = db.devices or {}
  db.seen = db.seen or {}; db.wd = db.wd or {}; db.pending = db.pending or {}
  self.sessions, self.codes, self.throttle = {}, {}, {}
  if not db.house then
    local n = self:new_account_number()
    db.accounts[n] = { n = n, owner = self.name .. " (house)", salt = "x", pin = "x", bal = 0,
      created = self.clock(), internal = true, hist = {} }
    db.house = n
  end
  return self
end

function Bank:full(n) return string.format("%02d-%s", self.no, n) end
function Bank:house() return self.db.accounts[self.db.house] end

function Bank:new_account_number()
  for _ = 1, 100 do
    local n = tostring(100000 + self.rand_int(900000))
    if not self.db.accounts[n] then return n end
  end
  error("cannot allocate account number")
end

function Bank:hash_pin(salt, pin)
  local h = salt .. pin
  for _ = 1, self.pin_rounds do h = sha.hex(h .. salt) end
  return h
end

local function push_hist(a, e)
  a.hist = a.hist or {}
  table.insert(a.hist, 1, e)
  while #a.hist > 12 do table.remove(a.hist) end
end

function Bank:credit(a, amt, kind, memo, peer)
  a.bal = a.bal + amt
  push_hist(a, { t = self.clock(), k = kind, amt = amt, memo = memo, peer = peer, bal = a.bal })
end
function Bank:debit(a, amt, kind, memo, peer)
  a.bal = a.bal - amt
  push_hist(a, { t = self.clock(), k = kind, amt = -amt, memo = memo, peer = peer, bal = a.bal })
end

local function mask(owner)
  owner = owner or "?"
  return owner:sub(1, 3) .. string.rep("*", math.max(0, #owner - 3))
end

---------------------------------------------------------------- devices (admin API)
function Bank:add_device(id, dtype, acct, limit)
  if self.db.devices[id] then return nil, "exists" end
  if dtype ~= "atm" and dtype ~= "shop" then return nil, "type" end
  if dtype == "shop" and not (acct and self.db.accounts[acct]) then return nil, "no_account" end
  local key = self.rand_hex(32)
  self.db.devices[id] = { type = dtype, key = key, acct = acct, limit = limit, created = self.clock() }
  self.save()
  return key
end

---------------------------------------------------------------- core money movement
-- Move `amt` from local account `a` to full id `to`.  o = { fee=, kind=, txid= }
function Bank:pay(a, to, amt, memo, o)
  o = o or {}
  local bb, nn = parse_full(to)
  if not bb then return fail("no_account") end
  if not valid_amt(amt) then return fail("bad_request") end
  local fee = o.fee or 0
  if a.bal < amt + fee then return fail("funds") end
  local kind = o.kind or "xfer"

  if bb == self.no then
    local d = self.db.accounts[nn]
    if not d or d.internal then return fail("no_account") end
    if d == a then return fail("bad_request") end
    self:debit(a, amt, kind, memo, to)
    self:credit(d, amt, kind .. "_in", memo, self:full(a.n))
    if fee > 0 then self:debit(a, fee, "fee", "fee"); self:credit(self:house(), fee, "fee", "fee from " .. a.n) end
    self.log({ t = self.clock(), k = kind, from = self:full(a.n), to = to, amt = amt, fee = fee, memo = memo })
    self.save()
    return { ok = true, bal = a.bal, fee = fee }
  end

  -- interbank: debit now, persist, then ask the clearing house to credit the other bank
  local txid = o.txid or (string.format("%02d", self.no) .. self.rand_hex(14))
  self:debit(a, amt, kind, memo, to)
  if fee > 0 then self:debit(a, fee, "fee", "interbank fee"); self:credit(self:house(), fee, "fee", "fee from " .. a.n) end
  self.db.pending[txid] = { acct = a.n, to = to, amt = amt, fee = fee, memo = memo, t = self.clock() }
  self.save()
  local r = self.net.route and self.net.route(bb, "credit",
    { to = nn, amount = amt, from = self:full(a.n), memo = memo, txid = txid })
  if r == nil or r.unknown then
    -- Unknown outcome: money may or may not have arrived. Never guess: keep it pending for the bank owner.
    return fail("unknown", { txid = txid })
  end
  self.db.pending[txid] = nil
  if not r.ok then
    self:credit(a, amt, "refund", "refund " .. (r.err or ""), to)
    if fee > 0 then self:credit(a, fee, "refund", "fee refund"); self:debit(self:house(), fee, "fee", "refunded") end
    self.save()
    return fail(r.err or "denied", { msg = r.msg })
  end
  self.log({ t = self.clock(), k = kind, from = self:full(a.n), to = to, amt = amt, fee = fee, memo = memo, txid = txid })
  self.save()
  return { ok = true, bal = a.bal, fee = fee }
end

---------------------------------------------------------------- sessions
function Bank:session(dev, tok)
  local s = tok and self.sessions[tok]
  if not s or s.dev ~= dev.id or s.exp < self.clock() then
    if tok then self.sessions[tok] = nil end
    return nil
  end
  local a = self.db.accounts[s.acct]
  if not a or a.frozen then return nil end
  s.exp = self.clock() + SESSION_MS
  return a
end

---------------------------------------------------------------- dispatcher
local ROLES = {
  atm  = { open = 1, login = 1, logout = 1, deposit = 1, withdraw = 1, reverse = 1, transfer = 1, lookup = 1,
           history = 1, change_pin = 1, gen_code = 1, status = 1 },
  shop = { redeem = 1, pay_out = 1, lookup = 1, market = 1, status = 1 },
  exchange = { x_credit = 1, x_redeem = 1, x_lookup = 1 },
}
local IDEMPOTENT = { deposit = 1, withdraw = 1, transfer = 1, redeem = 1, pay_out = 1 }
local MUTATES = { open = 1, deposit = 1, withdraw = 1, reverse = 1, transfer = 1, change_pin = 1, status = 1,
                  redeem = 1, pay_out = 1, x_credit = 1, x_redeem = 1 }

function Bank:handle(devid, m)
  local dev
  if devid == "exchange" then dev = { id = "exchange", type = "exchange" }
  else dev = self.db.devices[devid]; if dev then dev.id = devid end end
  if not dev or dev.disabled then return fail("denied") end
  local allowed = ROLES[dev.type]
  local h = allowed and allowed[m.type] and self["h_" .. m.type]
  if not h then return fail("denied") end

  local ikey = IDEMPOTENT[m.type] and m.ref and (devid .. ":" .. m.ref)
  if ikey and self.db.seen[ikey] then return self.db.seen[ikey].r end

  local r = h(self, dev, m)
  if ikey then
    self.db.seen[ikey] = { t = self.clock(), r = r }
    self:prune()
  end
  if MUTATES[m.type] then self.save() end
  return r
end

function Bank:prune()
  local seen, n = self.db.seen, 0
  for _ in pairs(seen) do n = n + 1 end
  if n > 2000 then
    local arr = {}
    for k, v in pairs(seen) do arr[#arr + 1] = { k, v.t } end
    table.sort(arr, function(x, y) return x[2] < y[2] end)
    for i = 1, 1000 do seen[arr[i][1]] = nil end
  end
  local wn = 0
  for _ in pairs(self.db.wd) do wn = wn + 1 end
  if wn > 600 then
    local arr = {}
    for k, v in pairs(self.db.wd) do arr[#arr + 1] = { k, v.t } end
    table.sort(arr, function(x, y) return x[2] < y[2] end)
    for i = 1, 300 do self.db.wd[arr[i][1]] = nil end
  end
end

---------------------------------------------------------------- handlers: ATM
function Bank:h_open(dev, m)
  local owner = tostring(m.owner or ""):gsub("[^%w _%.%-]", "")
  owner = owner:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 16)
  if #owner < 2 then return fail("bad_request", { msg = "Name too short" }) end
  if not tostring(m.pin or ""):match("^%d%d%d%d$") then return fail("bad_request", { msg = "PIN must be 4 digits" }) end
  local count = 0
  for _, a in pairs(self.db.accounts) do
    if not a.internal and a.owner:lower() == owner:lower() then count = count + 1 end
  end
  if count >= (self.fees.max_accounts_per_owner or 3) then return fail("exists") end
  local n = self:new_account_number()
  local salt = self.rand_hex(16)
  self.db.accounts[n] = { n = n, owner = owner, salt = salt, pin = self:hash_pin(salt, m.pin), bal = 0,
    created = self.clock(), hist = {} }
  return { ok = true, acct = self:full(n), owner = owner }
end

function Bank:h_login(dev, m)
  local bb, n = parse_full(m.acct)
  local a = bb == self.no and self.db.accounts[n]
  if not a or a.internal then return fail("auth") end
  local now = self.clock()
  if (a.lock or 0) > now then return fail("locked") end
  if a.frozen then return fail("frozen") end
  if self:hash_pin(a.salt, tostring(m.pin or "")) ~= a.pin then
    a.fails = (a.fails or 0) + 1
    if a.fails >= 3 then a.fails = 0; a.lock = now + 300000 end
    self.save()
    return fail("auth")
  end
  a.fails = 0
  local tok = self.rand_hex(24)
  self.sessions[tok] = { acct = n, dev = dev.id, exp = now + SESSION_MS }
  return { ok = true, tok = tok, owner = a.owner, bal = a.bal, acct = self:full(n) }
end

function Bank:h_logout(dev, m) self.sessions[m.tok or ""] = nil; return { ok = true } end

function Bank:h_deposit(dev, m)
  local a = self:session(dev, m.tok); if not a then return fail("session") end
  if not valid_amt(m.amount) then return fail("bad_request") end
  local fee = math.floor(m.amount * (self.fees.deposit_pct or 0) + 0.5)
  self:credit(a, m.amount - fee, "dep", "ATM " .. dev.id)
  if fee > 0 then self:credit(self:house(), fee, "fee", "deposit fee " .. a.n) end
  self.log({ t = self.clock(), k = "deposit", to = self:full(a.n), amt = m.amount, fee = fee, dev = dev.id, ref = m.ref })
  return { ok = true, bal = a.bal, fee = fee }
end

function Bank:h_withdraw(dev, m)
  local a = self:session(dev, m.tok); if not a then return fail("session") end
  if not valid_amt(m.amount) then return fail("bad_request") end
  local fee = math.floor(m.amount * (self.fees.withdraw_pct or 0) + 0.5)
  if a.bal < m.amount + fee then return fail("funds") end
  self:debit(a, m.amount, "wd", "ATM " .. dev.id)
  if fee > 0 then self:debit(a, fee, "fee", "withdraw fee"); self:credit(self:house(), fee, "fee", "withdraw fee " .. a.n) end
  if m.ref then self.db.wd[dev.id .. ":" .. m.ref] = { acct = a.n, principal = m.amount, fee = fee, back = 0, t = self.clock() } end
  self.log({ t = self.clock(), k = "withdraw", from = self:full(a.n), amt = m.amount, fee = fee, dev = dev.id, ref = m.ref })
  return { ok = true, bal = a.bal, fee = fee }
end

-- ATM could not dispense everything: give back `amount` (default: all) of a previous withdrawal
function Bank:h_reverse(dev, m)
  local w = self.db.wd[dev.id .. ":" .. tostring(m.ref)]
  if not w then return fail("bad_request") end
  local a = self.db.accounts[w.acct]
  local n = math.min(m.amount or (w.principal - w.back), w.principal - w.back)
  if n <= 0 then return fail("bad_request") end
  w.back = w.back + n
  self:credit(a, n, "refund", "ATM refund")
  if w.back == w.principal and w.fee > 0 then
    self:credit(a, w.fee, "refund", "fee refund"); self:debit(self:house(), w.fee, "fee", "refunded"); w.fee = 0
  end
  self.log({ t = self.clock(), k = "reverse", to = self:full(a.n), amt = n, dev = dev.id, ref = m.ref })
  return { ok = true, bal = a.bal }
end

function Bank:h_transfer(dev, m)
  local a = self:session(dev, m.tok); if not a then return fail("session") end
  if not valid_amt(m.amount) then return fail("bad_request") end
  local bb = parse_full(m.to)
  if not bb then return fail("no_account") end
  local fee = math.floor(m.amount * (self.fees.transfer_pct or 0) + 0.5)
  if bb ~= self.no then fee = fee + (self.fees.interbank_flat or 0) end
  return self:pay(a, m.to, m.amount, tostring(m.memo or ""):sub(1, 24), { fee = fee, kind = "xfer" })
end

function Bank:h_lookup(dev, m)
  local bb, n = parse_full(m.acct)
  if not bb then return fail("no_account") end
  if bb == self.no then
    local a = self.db.accounts[n]
    if not a or a.internal then return fail("no_account") end
    return { ok = true, name = mask(a.owner), bank = self.name }
  end
  local r = self.net.route and self.net.route(bb, "lookup", { acct = n })
  if not r then return fail("net") end
  return r
end

function Bank:h_history(dev, m)
  local a = self:session(dev, m.tok); if not a then return fail("session") end
  return { ok = true, hist = a.hist or {}, bal = a.bal }
end

function Bank:h_change_pin(dev, m)
  local a = self:session(dev, m.tok); if not a then return fail("session") end
  if self:hash_pin(a.salt, tostring(m.old or "")) ~= a.pin then return fail("auth") end
  if not tostring(m.new or ""):match("^%d%d%d%d$") then return fail("bad_request", { msg = "PIN must be 4 digits" }) end
  a.salt = self.rand_hex(16); a.pin = self:hash_pin(a.salt, m.new)
  return { ok = true }
end

function Bank:h_gen_code(dev, m)
  local a = self:session(dev, m.tok); if not a then return fail("session") end
  if not valid_amt(m.max) then return fail("bad_request") end
  for c, e in pairs(self.codes) do if e.acct == a.n then self.codes[c] = nil end end   -- one live code per account
  local code
  repeat code = string.format("%02d%06d", self.no, self.rand_int(1000000)) until not self.codes[code]
  self.codes[code] = { acct = a.n, max = m.max, exp = self.clock() + CODE_MS }
  return { ok = true, code = code, ttl = CODE_MS / 1000 }
end

function Bank:h_status(dev, m)
  dev.status = { t = self.clock(), vault = m.vault, info = m.info }
  return { ok = true, t = self.clock() }
end

---------------------------------------------------------------- handlers: shops
function Bank:redeem_local(code, amt, payee, memo)
  local c = self.codes[code]
  if not c or c.exp < self.clock() then self.codes[code] = nil; return fail("code") end
  if amt > c.max then return fail("limit", { msg = "Code limit too low" }) end
  local a = self.db.accounts[c.acct]
  if not a or a.frozen then return fail("frozen") end
  local r = self:pay(a, payee, amt, memo, { kind = "shop" })
  if r.ok then self.codes[code] = nil; r.bal = nil end     -- never leak the customer's balance to a shop
  return r
end

function Bank:h_redeem(dev, m)
  if not dev.acct then return fail("denied") end
  if not valid_amt(m.amount) then return fail("bad_request") end
  local now = self.clock()
  local th = self.throttle[dev.id] or { n = 0, t = now }
  if now - th.t > 60000 then th = { n = 0, t = now } end
  self.throttle[dev.id] = th
  if th.n >= 8 then return fail("throttle") end

  local code = tostring(m.code or "")
  if not code:match("^%d%d%d%d%d%d%d%d$") then th.n = th.n + 1; return fail("code") end
  local bb = tonumber(code:sub(1, 2))
  local payee, memo = self:full(dev.acct), tostring(m.memo or ""):sub(1, 24)
  local r
  if bb == self.no then r = self:redeem_local(code, m.amount, payee, memo)
  else
    r = self.net.route and self.net.route(bb, "redeem", { code = code, amount = m.amount, payee = payee, memo = memo })
    if not r then return fail("unknown") end
  end
  if not r.ok and (r.err == "code") then th.n = th.n + 1 end
  return r
end

function Bank:h_x_redeem(dev, m)
  if not (m.code and valid_amt(m.amount) and m.payee) then return fail("bad_request") end
  return self:redeem_local(tostring(m.code), m.amount, m.payee, m.memo)
end

function Bank:h_pay_out(dev, m)
  local a = dev.acct and self.db.accounts[dev.acct]
  if not a or a.frozen then return fail("denied") end
  if dev.limit and m.amount and m.amount > dev.limit then return fail("limit") end
  return self:pay(a, m.to, m.amount, tostring(m.memo or ""):sub(1, 24), { kind = "shop" })
end

local MARKET_OPS = { prices = 1, report = 1 }
function Bank:h_market(dev, m)
  if not MARKET_OPS[m.op] or not self.net.market then return fail("denied") end
  local args = m.args or {}
  if m.op == "report" then args.shop = dev.id end
  local r = self.net.market(m.op, args)
  return r or fail("net")
end

---------------------------------------------------------------- handlers: from the exchange
function Bank:h_x_credit(dev, m)
  local txid = m.txid
  if type(txid) ~= "string" or not valid_amt(m.amount) then return fail("bad_request") end
  local key = "x:" .. txid
  if self.db.seen[key] then return self.db.seen[key].r end
  local a = self.db.accounts[tostring(m.to)]
  if not a or a.internal then return fail("no_account") end
  self:credit(a, m.amount, "xfer_in", m.memo, m.from)
  local r = { ok = true }
  self.db.seen[key] = { t = self.clock(), r = r }
  self.log({ t = self.clock(), k = "interbank_in", from = m.from, to = self:full(a.n), amt = m.amount, memo = m.memo, txid = txid })
  self:prune()
  return r
end

function Bank:h_x_lookup(dev, m)
  local a = self.db.accounts[tostring(m.acct)]
  if not a or a.internal then return fail("no_account") end
  return { ok = true, name = mask(a.owner), bank = self.name }
end

---------------------------------------------------------------- admin helpers
function Bank:total_deposits()
  local t = 0
  for _, a in pairs(self.db.accounts) do t = t + a.bal end
  return t
end

-- resolve a pending interbank tx: "refund" (money never arrived) or "drop" (it did arrive)
function Bank:resolve_pending(txid, action)
  local p = self.db.pending[txid]
  if not p then return nil, "no such tx" end
  if action == "refund" then
    local a = self.db.accounts[p.acct]
    self:credit(a, p.amt, "refund", "pending refund", p.to)
    if p.fee > 0 then self:credit(a, p.fee, "refund", "fee refund"); self:debit(self:house(), p.fee, "fee", "refunded") end
  end
  self.db.pending[txid] = nil
  self.save()
  return true
end

return Bank
