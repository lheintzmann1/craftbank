local P = require("common.pricing")
local items = require("common.items")

test("price table loads, diamond pegged at 1000", function()
  eq(items.byId["minecraft:diamond"].base, 100000)
  eq(items.byId["minecraft:diamond_block"].base, 900000)
  truthy(#items.list > 250)
  for _, e in ipairs(items.list) do truthy(e.base >= 1 and e.k >= 16 and e.sens > 0, e.id) end
end)

test("buying raises price, selling lowers it, bounded", function()
  local par = items.byId["minecraft:iron_ingot"]
  local p0 = P.mid(par, 0, 1); eq(p0, par.base)
  truthy(P.mid(par, 300, 1) > p0); truthy(P.mid(par, -300, 1) < p0)
  truthy(P.mid(par, 1e9, 1) <= par.base * P.MAX_MULT + 1e-6)
  truthy(P.mid(par, -1e9, 1) >= par.base * P.MIN_MULT - 1e-6)
end)

test("peg: diamond never moves", function()
  local par = items.byId["minecraft:diamond"]
  eq(P.mid(par, 99999, 3), par.base); eq(P.mid(par, -99999, 0.2), par.base)
end)

test("no arbitrage: buy q then sell q never profits", function()
  for _, id in ipairs({ "minecraft:iron_ingot", "minecraft:cobblestone", "minecraft:emerald", "minecraft:diamond_pickaxe" }) do
    local par = items.byId[id]
    for _, start in ipairs({ -2 * par.k, 0, par.k }) do
      for _, q in ipairs({ 1, 10, 64, 500 }) do
        local spend = P.quote(par, start, 1, "buy", q, 0.06)
        local back = P.quote(par, start + P.delta("buy", q), 1, "sell", q, 0.06)
        truthy(back <= spend, string.format("%s start=%d q=%d spend=%d back=%d", id, start, q, spend, back))
      end
    end
  end
end)

test("spread: sell < buy at the same state", function()
  local par = items.byId["minecraft:gold_ingot"]
  truthy(P.quote(par, 0, 1, "sell", 10, 0.08) < P.quote(par, 0, 1, "buy", 10, 0.08))
end)

test("big orders slide the price (slippage)", function()
  local par = items.byId["minecraft:iron_ingot"]
  local small = P.quote(par, 0, 1, "buy", 10, 0) / 10
  local big = P.quote(par, 0, 1, "buy", 2000, 0) / 2000
  truthy(big > small * 1.5, "expected visible slippage")
end)

test("decay brings N back toward zero", function()
  local h = 3600000
  eq(math.floor(P.decay(1000, 6 * h, 6)), 500)
  truthy(P.decay(1000, 60 * h, 6) < 1)
end)
