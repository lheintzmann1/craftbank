-- Pure-Lua SHA-256 + HMAC (uses bit32, available in CC:Tweaked and Lua 5.2/5.3 compat).
local band, bor, bxor, bnot, rshift, rrot =
  bit32.band, bit32.bor, bit32.bxor, bit32.bnot, bit32.rshift, bit32.rrotate

local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function compress(H, w)
  for i = 17, 64 do
    local a, b = w[i - 15], w[i - 2]
    local s0 = bxor(rrot(a, 7), rrot(a, 18), rshift(a, 3))
    local s1 = bxor(rrot(b, 17), rrot(b, 19), rshift(b, 10))
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % 4294967296
  end
  local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
  for i = 1, 64 do
    local S1 = bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25))
    local ch = bxor(band(e, f), band(bnot(e), g))
    local t1 = (h + S1 + ch + K[i] + w[i]) % 4294967296
    local S0 = bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22))
    local maj = bxor(band(a, b), band(a, c), band(b, c))
    local t2 = (S0 + maj) % 4294967296
    h, g, f, e, d, c, b, a = g, f, e, (d + t1) % 4294967296, c, b, a, (t1 + t2) % 4294967296
  end
  H[1] = (H[1] + a) % 4294967296; H[2] = (H[2] + b) % 4294967296
  H[3] = (H[3] + c) % 4294967296; H[4] = (H[4] + d) % 4294967296
  H[5] = (H[5] + e) % 4294967296; H[6] = (H[6] + f) % 4294967296
  H[7] = (H[7] + g) % 4294967296; H[8] = (H[8] + h) % 4294967296
end

local M = {}

-- raw 32-byte digest
function M.digest(msg)
  local H = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  local len = #msg
  msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
  local bits = len * 8
  msg = msg .. string.char(0, 0, 0, 0,
    math.floor(bits / 16777216) % 256, math.floor(bits / 65536) % 256,
    math.floor(bits / 256) % 256, bits % 256)
  local w = {}
  for pos = 1, #msg, 64 do
    for i = 1, 16 do
      local a, b, c, d = msg:byte(pos + (i - 1) * 4, pos + (i - 1) * 4 + 3)
      w[i] = a * 16777216 + b * 65536 + c * 256 + d
    end
    compress(H, w)
  end
  local out = {}
  for i = 1, 8 do
    local v = H[i]
    out[i] = string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
  end
  return table.concat(out)
end

function M.tohex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
function M.hex(msg) return M.tohex(M.digest(msg)) end

function M.hmac(key, msg)
  if #key > 64 then key = M.digest(key) end
  key = key .. string.rep("\0", 64 - #key)
  local ipad = key:gsub(".", function(c) return string.char(bxor(c:byte(), 0x36)) end)
  local opad = key:gsub(".", function(c) return string.char(bxor(c:byte(), 0x5c)) end)
  return M.digest(opad .. M.digest(ipad .. msg))
end

-- constant-time-ish compare
function M.equal(a, b)
  if #a ~= #b then return false end
  local diff = 0
  for i = 1, #a do diff = bor(diff, bxor(a:byte(i), b:byte(i))) end
  return diff == 0
end

return M
