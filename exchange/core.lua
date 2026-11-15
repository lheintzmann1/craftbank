-- EXCHANGE CORE: the "central bank + stock exchange" of the server.
--   1. Clearing house: routes interbank payments, tracks each bank's net position, enforces credit limits.
--   2. Market: owns the live price state of every item (net flow N), applies trades, server stats and events.
-- Pure logic; the server injects db, save, clock, deliver(bankNo, msg)->reply|nil, rand(), cfg.
local items   = require("common.items")
local pricing = require("common.pricing")

local X = {}
X.__index = X

local function fail(err, msg, extra)
  local r = { ok = false, err = err, msg = msg or err }
  if extra then for k, v in pairs(extra) do r[k] = v end end
  return r
end

local EVENT_TEMPLATES = {
  { cat = "ore",    mult = 0.80, mins = 90, text = "Mining boom: ore prices dip" },
  { cat = "ore",    mult = 1.25, mins = 90, text = "Ore shortage: prices climb" },
  { cat = "farm",   mult = 1.30, mins = 60, text = "Drought hits crops" },
  { cat = "food",   mult = 0.80, mins = 60, text = "Harvest festival: food is cheap" },
  { cat = "mob",    mult = 1.25, mins = 60, text = "Monster surge: drops in demand" },
  { cat = "wood",   mult = 0.85, mins = 75, text = "Lumber surplus" },
  { cat = "nether", mult = 1.30, mins = 60, text = "Nether trade route disrupted" },
  { cat = "end",    mult = 1.25, mins = 60, text = "End expedition lost at sea" },
  { cat = "redstone", mult = 1.20, mins = 60, text = "Engineers' convention" },
  { item = "minecraft:emerald", mult = 1.40, mins = 60, text = "Villager emerald craze" },
  { item = "minecraft:ender_pearl", mult = 1.35, mins = 45, text = "Pearl shortage" },
  { item = "minecraft:netherite_ingot", mult = 1.25, mins = 60, text = "Netherite fever" },
}
X.EVENT_TEMPLATES = EVENT_TEMPLATES

function X.new(o)
  local self = setmetatable({}, X)
  self.db, self.save, self.clock, self.deliver = o.db, o.save or function() end, o.clock, o.deliver
  self.cfg = o.cfg or {}
  self.rand = o.rand or math.random
  local db = self.db
  db.banks = db.banks or {}; db.pos = db.pos or {}; db.items = db.items or {}
  db.events = db.events or {}; db.stats = db.stats or {}; db.tx = db.tx or {}
  db.stat_totals = db.stat_totals or {}
  return self
end

---------------------------------------------------------------- bank registry (admin)
function X:add_bank(no, name, key, limit, computer)
  if self.db.banks[no] then return nil, "exists" end
  self.db.banks[no] = { name = name, key = key, limit = limit, computer = computer }
  self.db.pos[no] = self.db.pos[no] or 0
  self.save()
  return true
end

function X:limit_of(no) return (self.db.banks[no] and self.db.banks[no].limit) or self.cfg.default_limit or 5000000 end

-- admin: bank `a` physically paid `b` (diamonds changed hands in the real world) -> clear the debt
function X:settle(a, b, amt)
  if not (self.db.banks[a] and self.db.banks[b]) then return nil, "unknown bank" end
  self.db.pos[a] = (self.db.pos[a] or 0) + amt
  self.db.pos[b] = (self.db.pos[b] or 0) - amt
  self.save()
  return true
end

---------------------------------------------------------------- market state
function X:halflife() return self.cfg.halflife_hours or pricing.DEFAULT_HALFLIFE_H end

function X:flow(id, now)
  local st = self.db.items[id]
  if not st then return 0 end
  return pricing.decay(st.N, now - st.t, self:halflife())
end

function X:set_flow(id, N, now)
  local par = items.byId[id]
  if not par then return end
  local lim = par.k * 8
  self.db.items[id] = { N = math.max(-lim, math.min(lim, N)), t = now }
end

function X:event_mult(id, now)
  local par, m = items.byId[id], 1
  if not par or par.peg then return 1 end
  for _, e in ipairs(self.db.events) do
    if e.exp > now and (e.item == id or (e.cat and e.cat == par.cat)) then m = m * e.mult end
  end
  return m
end

function X:state(id, now)
  return { self:flow(id, now), self:event_mult(id, now) }
end

function X:mid(id, now)
  local par = items.byId[id]
  return par and pricing.mid(par, self:flow(id, now), self:event_mult(id, now))
end

function X:apply_trade(id, side, qty, now)
  if not items.byId[id] then return false end
  self:set_flow(id, self:flow(id, now) + pricing.delta(side, qty), now)
  return true
end

-- stats = { mined = {id=total}, crafted = {...}, used = {...}, broken = {...} } (cumulative totals from the bridge)
local STAT_SIGN = { mined = -1, crafted = -1, used = 1, broken = 1 }
function X:apply_stats(stats, now)
  local w = self.cfg.stat_weights or { mined = 0.5, crafted = 0.3, used = 0.25, broken = 0.5 }
  local applied = 0
  for cat, sign in pairs(STAT_SIGN) do
    for id, total in pairs(stats[cat] or {}) do
      local par = items.byId[id]
      if par and type(total) == "number" then
        local key = cat .. ":" .. id
        local last = self.db.stat_totals[key]
        self.db.stat_totals[key] = total
        if last and total > last then
          local dN = sign * (total - last) * (w[cat] or 0)
          dN = math.max(-par.k, math.min(par.k, dN))     -- one poll can never move more than K
          self:set_flow(id, self:flow(id, now) + dN, now)
          applied = applied + 1
        end
      end
    end
  end
  return applied
end

---------------------------------------------------------------- events
function X:tick(now)
  local keep = {}
  for _, e in ipairs(self.db.events) do if e.exp > now then keep[#keep + 1] = e end end
  self.db.events = keep
  if self.cfg.events == false then return end
  if not self.db.next_event then self.db.next_event = now + 30 * 60000 end
  if now >= self.db.next_event then
    local t = EVENT_TEMPLATES[1 + math.floor(self.rand() * #EVENT_TEMPLATES) % #EVENT_TEMPLATES]
    self:add_event(t.item, t.cat, t.mult, t.mins, t.text, now)
    self.db.next_event = now + (30 + math.floor(self.rand() * 60)) * 60000
  end
end

function X:add_event(item, cat, mult, mins, text, now)
  table.insert(self.db.events, { item = item, cat = cat, mult = mult, exp = now + mins * 60000, text = text })
  self.save()
end

---------------------------------------------------------------- request handling
function X:handle(from, m)
  if m.type == "route" then return self:route(from, m) end
  if m.type == "market" then return self:market(from, m) end
  return fail("denied")
end

local ROUTE_OPS = { credit = 1, redeem = 1, lookup = 1 }
function X:route(from, m)
  local dest = self.db.banks[m.dest]
  if not dest then return fail("no_account", "Unknown bank " .. tostring(m.dest)) end
  if not ROUTE_OPS[m.op] then return fail("denied") end
  local args = m.args or {}
  local amt, txid = args.amount, args.txid
  if m.op == "credit" then
    if type(amt) ~= "number" or amt <= 0 or type(txid) ~= "string" then return fail("bad_request") end
    if self.db.tx[txid] then return self.db.tx[txid] end                      -- idempotent retry
    if (self.db.pos[from] or 0) - amt < -self:limit_of(from) then
      return fail("limit", "Bank interbank limit reached")
    end
  end
  local msg = { type = "x_" .. m.op }
  for k, v in pairs(args) do msg[k] = v end
  local r = self.deliver(m.dest, msg)
  if not r then return { ok = false, err = "net", unknown = true, msg = "Destination bank unreachable" } end
  if m.op == "credit" and r.ok then
    self.db.pos[from] = (self.db.pos[from] or 0) - amt
    self.db.pos[m.dest] = (self.db.pos[m.dest] or 0) + amt
    self.db.tx[txid] = r
    local n = 0
    for _ in pairs(self.db.tx) do n = n + 1 end
    if n > 1500 then self.db.tx = { [txid] = r } end                         -- crude prune; dest banks dedupe too
    self.save()
  end
  return r
end

function X:market(from, m)
  local now = self.clock()
  local a = m.args or {}
  if m.op == "prices" then
    local out = {}
    for _, id in ipairs(a.items or {}) do
      if items.byId[id] then out[id] = self:state(id, now) end
    end
    return { ok = true, items = out, digest = items.digest, ts = now }
  elseif m.op == "report" then
    if a.side ~= "buy" and a.side ~= "sell" then return fail("bad_request") end
    if type(a.qty) ~= "number" or a.qty <= 0 or a.qty > 100000 then return fail("bad_request") end
    if not self:apply_trade(a.item, a.side, a.qty, now) then return fail("bad_request") end
    return { ok = true }
  end
  return fail("denied")
end

return X
