-- Regenerates docs/PRICES.md from data/base_prices.lua:   lua tools/gen_prices_md.lua > docs/PRICES.md
package.path = "./?.lua;" .. package.path
local items, money = require("common.items"), require("common.money")
print("# Reference prices\n")
print("Generated from `data/base_prices.lua` (checksum `" .. items.digest .. "`, " .. #items.list .. " items). 1 diamond = 1,000 Cr.")
print("Live market prices move around these (see DESIGN.md). *K* = liquidity: net units that move the price roughly 2x.\n")
for _, cat in ipairs(items.cats) do
  print("## " .. cat .. "\n\n| Item | Base price (Cr) | K |\n|---|---:|---:|")
  for _, e in ipairs(items.list) do
    if e.cat == cat then print(string.format("| %s%s | %s | %d |", items.display(e.id), e.peg and " (pegged)" or "", money.fmt(e.base), e.k)) end
  end
  print()
end
