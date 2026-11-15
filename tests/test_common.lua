local sha = require("common.sha256")
local serial = require("common.serial")
local money = require("common.money")
local proto = require("common.protocol")

test("sha256 known vectors", function()
  eq(sha.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  eq(sha.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  eq(sha.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
     "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
  eq(sha.hex(string.rep("a", 1000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
end)

test("hmac-sha256 RFC 4231 case 2", function()
  eq(sha.tohex(sha.hmac("Jefe", "what do ya want for nothing?")),
     "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
end)

test("serial round trip", function()
  local t = { a = 1, b = "x\ny\"z", c = { 1, 2, { d = true } }, ["end"] = 5, [10] = 7, f = 0.1, big = 123456789012 }
  local r = serial.decode(serial.encode(t))
  eq(r.a, 1); eq(r.b, "x\ny\"z"); eq(r.c[3].d, true); eq(r["end"], 5); eq(r[10], 7); eq(r.f, 0.1); eq(r.big, 123456789012)
  truthy(serial.decode("os.exit()") == nil, "code must not execute")
end)

test("money format/parse", function()
  eq(money.fmt(123456), "1,234.56"); eq(money.fmt(100000), "1,000.00"); eq(money.short(100000), "1,000")
  eq(money.fmt(-5), "-0.05"); eq(money.fmt(123456789), "1,234,567.89")
  eq(money.parse("12"), 1200); eq(money.parse("12.5"), 1250); eq(money.parse("abc"), nil)
end)

test("protocol: seal/open, tamper, replay, wrong key", function()
  local key = "k3y"
  local keyfn = function(d) if d == "dev1" then return key end end
  local pkt = proto.seal("dev1", key, { type = "login", pin = "1234" })
  truthy(not pkt.c:find("1234", 1, true), "payload must be encrypted")
  local seen = {}
  local m, dev = proto.open(keyfn, pkt, seen)
  eq(m.type, "login"); eq(m.pin, "1234"); eq(dev, "dev1")
  local _, why = proto.open(keyfn, pkt, seen); eq(why, "replay")
  local bad = proto.seal("dev1", key, { x = 1 }); bad.c = bad.c:sub(1, -2) .. "Z"
  local _, why2 = proto.open(keyfn, bad); eq(why2, "bad_mac")
  local other = proto.seal("dev1", "wrong", { x = 1 })
  local _, why3 = proto.open(keyfn, other); eq(why3, "bad_mac")
  local _, why4 = proto.open(keyfn, proto.seal("nobody", key, { x = 1 })); eq(why4, "unknown_device")
end)

test("rng produces distinct values", function()
  local a, b = proto.rand_hex(16), proto.rand_hex(16)
  truthy(a ~= b); eq(#a, 16)
  for _ = 1, 100 do local v = proto.rand_int(10); truthy(v >= 0 and v < 10) end
end)
