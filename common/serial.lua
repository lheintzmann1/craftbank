-- Tiny, dependency-free serializer (Lua tables <-> text). Works in CC and plain Lua.
local M = {}

local RESERVED = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%a+") do RESERVED[w] = true end

local function ser(v, out)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("serial: bad number") end
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.17g", v) end
  elseif t == "string" then out[#out + 1] = (string.format("%q", v):gsub("\\\n", "\\n"))
  elseif t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "table" then
    out[#out + 1] = "{"
    local n = #v
    for i = 1, n do ser(v[i], out); out[#out + 1] = "," end
    for k, val in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
        if type(k) == "string" and k:match("^[%a_][%w_]*$") and not RESERVED[k] then out[#out + 1] = k .. "="
        else out[#out + 1] = "["; ser(k, out); out[#out + 1] = "]=" end
        ser(val, out); out[#out + 1] = ","
      end
    end
    out[#out + 1] = "}"
  else error("serial: cannot serialize " .. t) end
end

function M.encode(v) local out = {}; ser(v, out); return table.concat(out) end

function M.decode(s)
  local f, err = load("return " .. s, "serial", "t", {})
  if not f then return nil, err end
  local ok, res = pcall(f)
  if not ok then return nil, res end
  return res
end

return M
