-- DYNAMIC PRICE MODEL (pure functions, identical on every node)
--
-- Each item has one number: N = "net flow" (units).
--   player BUYS  from a shop  -> demand -> N goes up
--   player SELLS to  a shop   -> supply -> N goes down
--   mined / crafted (server stats) -> supply -> N goes down (a bit)
--   items used / broken        -> demand -> N goes up (a bit)
-- N decays toward 0 with a half-life, so prices drift back to the base price over time.
--
--   mid(N) = base * exp( sens * tanh(N / K) ) * event_multiplier
--
-- Because the price depends only on N (not on a running history), buying q then selling q returns
-- to the same price: no arbitrage loop, only the spread is lost. Large trades "slide" along the curve:
-- quote() integrates the price over the quantity.
local P = {}

P.DEFAULT_HALFLIFE_H = 6
P.MIN_MULT, P.MAX_MULT = 0.2, 5.0

local function tanh(x)
  if x > 20 then return 1 elseif x < -20 then return -1 end
  local e = math.exp(2 * x)
  return (e - 1) / (e + 1)
end

function P.decay(N, dt_ms, halflife_h)
  if dt_ms <= 0 then return N end
  return N * 0.5 ^ (dt_ms / ((halflife_h or P.DEFAULT_HALFLIFE_H) * 3600000))
end

-- mid price in cents (float) for item params `par`, net flow N, event multiplier ev
function P.mid(par, N, ev)
  if par.peg then return par.base end
  local m = math.exp(par.sens * tanh(N / par.k)) * (ev or 1)
  return par.base * math.max(P.MIN_MULT, math.min(P.MAX_MULT, m))
end

-- Total price in cents (integer) for `qty` units.
--   side = "buy"  : the player buys from the shop (pays more than mid)
--   side = "sell" : the player sells to the shop   (gets less than mid)
--   spread = total bid/ask spread (e.g. 0.08 -> +4% / -4% around mid)
function P.quote(par, N, ev, side, qty, spread)
  if qty <= 0 then return 0 end
  local dir = side == "buy" and 1 or -1
  local steps = math.min(24, math.max(1, math.ceil(qty / 4)))
  local per = qty / steps
  local a, total = P.mid(par, N, ev), 0
  for i = 1, steps do
    local b = P.mid(par, N + dir * per * i, ev)
    total = total + per * (a + b) / 2
    a = b
  end
  local half = (spread or 0) / 2
  if side == "buy" then return math.max(1, math.ceil(total * (1 + half) - 1e-9)) end
  return math.max(0, math.floor(total * (1 - half) + 1e-9))
end

-- net-flow change caused by a trade
function P.delta(side, qty) return side == "buy" and qty or -qty end

return P
