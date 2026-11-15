-- Secure request/response over rednet.
--   * every device has its own secret key (registered at its bank)
--   * packets are encrypted (SHA-256 counter-mode keystream) and authenticated (HMAC-SHA256)
--   * timestamps + nonces stop replays; PINs never travel in clear text
-- Rednet is a broadcast medium: anyone with a modem can *see* packets, but cannot read or forge them.
local sha    = require("common.sha256")
local serial = require("common.serial")
local const  = require("common.const")

local M = {}
M.PROTO = const.PROTOCOL
M.TTL   = 30000   -- ms a packet stays valid

local function now()
  if os.epoch then return os.epoch("utc") end
  return math.floor(os.time() * 1000)
end
M.now = now

---------------------------------------------------------------- randomness
local rng = sha.hex(tostring(now()) .. tostring(os.clock()) .. tostring(math.random()) ..
  tostring(os.getComputerID and os.getComputerID() or 0))
function M.rand_bytes(n)
  local out = {}
  while #table.concat(out) < n do
    rng = sha.hex(rng .. tostring(now()) .. tostring(os.clock()) .. tostring(math.random()))
    out[#out + 1] = sha.digest(rng)
  end
  return table.concat(out):sub(1, n)
end
function M.rand_hex(n) return sha.tohex(M.rand_bytes(math.ceil(n / 2))):sub(1, n) end
-- uniform integer 0..max-1 from the hash RNG
function M.rand_int(max)
  local b = M.rand_bytes(6)
  local v = 0
  for i = 1, 6 do v = v * 256 + b:byte(i) end
  return v % max
end

---------------------------------------------------------------- seal / open
local function keystream_xor(kenc, nonce, data)
  local out = {}
  for pos = 1, #data, 32 do
    local block = sha.digest(kenc .. nonce .. string.format("%08x", (pos - 1) / 32))
    for j = 0, math.min(31, #data - pos) do
      out[#out + 1] = string.char(bit32.bxor(data:byte(pos + j), block:byte(j + 1)))
    end
  end
  return table.concat(out)
end

local function subkeys(key) return sha.hmac(key, "enc"), sha.hmac(key, "mac") end

function M.seal(dev, key, tbl)
  tbl.ts = now()
  local nonce = M.rand_bytes(12)
  local kenc, kmac = subkeys(key)
  local ct = keystream_xor(kenc, nonce, serial.encode(tbl))
  return { v = 1, d = dev, n = nonce, c = ct, m = sha.hmac(kmac, dev .. nonce .. ct) }
end

-- keyfn(devid) -> key or nil ; seen = replay table (optional)
-- returns msg, devid   or   nil, reason
function M.open(keyfn, pkt, seen)
  if type(pkt) ~= "table" or pkt.v ~= 1 or type(pkt.d) ~= "string" or type(pkt.n) ~= "string"
     or type(pkt.c) ~= "string" or type(pkt.m) ~= "string" then return nil, "format" end
  local key = keyfn(pkt.d)
  if not key then return nil, "unknown_device" end
  local kenc, kmac = subkeys(key)
  if not sha.equal(sha.hmac(kmac, pkt.d .. pkt.n .. pkt.c), pkt.m) then return nil, "bad_mac" end
  local msg = serial.decode(keystream_xor(kenc, pkt.n, pkt.c))
  if type(msg) ~= "table" or type(msg.ts) ~= "number" then return nil, "garbled" end
  local t = now()
  if math.abs(t - msg.ts) > M.TTL then return nil, "stale" end
  if seen then
    if seen[pkt.n] then return nil, "replay" end
    seen[pkt.n] = t
    seen.__count = (seen.__count or 0) + 1
    if seen.__count > 400 then
      for k, ts in pairs(seen) do if k ~= "__count" and t - ts > M.TTL * 2 then seen[k] = nil; seen.__count = seen.__count - 1 end end
    end
  end
  return msg, pkt.d
end

---------------------------------------------------------------- rednet client
local function copy(t) local r = {}; for k, v in pairs(t) do r[k] = v end; return r end

-- o = { dev=, key=, host=hostname to look up, fixed=optional computer id }
function M.client(o)
  local c = { dev = o.dev, key = o.key, host = o.host, id = o.fixed }
  local function keyfn() return c.key end

  function c:resolve()
    if self.id then return self.id end
    self.id = rednet.lookup(M.PROTO, self.host)
    return self.id
  end

  -- returns reply table, or nil,"timeout"
  function c:call(msg, timeout, tries)
    msg = copy(msg)
    msg.rid = msg.rid or M.rand_hex(10)
    for _ = 1, tries or 1 do
      local id = self:resolve()
      if id then
        rednet.send(id, M.seal(self.dev, self.key, copy(msg)), M.PROTO)
        local timer = os.startTimer(timeout or 6)
        while true do
          local ev, a, b, p = os.pullEvent()
          if ev == "rednet_message" and p == M.PROTO then
            local r = M.open(keyfn, b)
            if r and r.rid == msg.rid then os.cancelTimer(timer); return r end
          elseif ev == "timer" and a == timer then break end
        end
        if not o.fixed then self.id = nil end   -- re-resolve next try
      end
    end
    return nil, "timeout"
  end
  return c
end

-- Server loop. opts = { hostname, keyfn, handle(devid,msg,from)->reply, spawn }
function M.serve(opts)
  rednet.host(M.PROTO, opts.hostname)
  local seen = {}
  while true do
    local from, pkt = rednet.receive(M.PROTO)
    opts.spawn(function()
      local msg, devid = M.open(opts.keyfn, pkt, seen)
      if not msg then return end
      local ok, reply = pcall(opts.handle, devid, msg, from)
      if not ok then reply = { ok = false, err = "internal", msg = tostring(reply) } end
      reply.rid = msg.rid
      rednet.send(from, M.seal(opts.label or opts.hostname, opts.keyfn(devid), reply), M.PROTO)
    end)
  end
end

return M
