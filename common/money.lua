-- Integer money helpers. Never do float math on balances.
local const = require("common.const")
local M = {}

local function commas(n)
  local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (s:gsub("^,", ""))
end

-- 123456 -> "1,234.56"
function M.fmt(cents)
  local neg = cents < 0
  cents = math.abs(math.floor(cents + 0.5))
  local whole, frac = math.floor(cents / const.SCALE), cents % const.SCALE
  return (neg and "-" or "") .. commas(string.format("%d", whole)) .. string.format(".%02d", frac)
end

-- Like fmt but drops ".00" (fits small screens): 100000 -> "1,000"
function M.short(cents)
  return (M.fmt(cents):gsub("%.00$", ""))
end

function M.fmtc(cents) return M.fmt(cents) .. " " .. const.CURRENCY_SYMBOL end

-- "12" / "12.5" / "12.50" -> cents (or nil)
function M.parse(str)
  local w, f = tostring(str):match("^(%d+)%.?(%d*)$")
  if not w then return nil end
  f = (f .. "00"):sub(1, 2)
  return tonumber(w) * const.SCALE + tonumber(f)
end

-- Multiply cents by a factor, round half up, stay an integer.
function M.mul(cents, factor) return math.floor(cents * factor + 0.5) end

return M
