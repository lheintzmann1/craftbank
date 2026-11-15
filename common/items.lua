-- Item catalogue built from data/base_prices.lua
local sha = require("common.sha256")
local list = require("data.base_prices")

local M = { list = list, byId = {} }

-- price sensitivity (how violently the price reacts to net buying/selling) by category
local SENS = { ore = 1.15, nether = 1.1, ["end"] = 1.0, mob = 1.0, farm = 1.0, food = 1.0, wood = 0.9,
  stone = 0.9, dye = 0.9, redstone = 0.9, misc = 0.7, tool = 0.5, armor = 0.5 }

local cat_order = {}
for _, e in ipairs(list) do
  local units = e.base / 100
  -- liquidity K: net units (buys-sells) that move the price ~2x. Cheap bulk items have a deep market.
  e.k    = e.k    or math.max(16, math.min(20000, math.floor(6000 / units ^ 0.6)))
  e.sens = e.sens or SENS[e.cat] or 1.0
  M.byId[e.id] = e
  if not cat_order[e.cat] then cat_order[e.cat] = true; M.cats = M.cats or {}; M.cats[#M.cats + 1] = e.cat end
end

-- checksum so nodes can detect they are running different price files
do
  local parts = {}
  for _, e in ipairs(list) do parts[#parts + 1] = e.id .. ":" .. e.base end
  M.digest = sha.hex(table.concat(parts, ";")):sub(1, 8)
end

-- "minecraft:iron_ingot" -> "Iron Ingot"
function M.display(id)
  local s = id:gsub("^[%w_]+:", ""):gsub("_", " ")
  return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

return M
