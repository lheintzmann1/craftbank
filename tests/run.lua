-- Run from the repo root:  lua tests/run.lua      (Lua 5.2/5.3 with bit32)
package.path = "./?.lua;" .. package.path
if not bit32 then error("need bit32 (Lua 5.2 or 5.3 with compat)") end
os.epoch = os.epoch or function() return math.floor(os.time() * 1000) end
printError = printError or function(...) io.stderr:write(table.concat({...}, " "), "\n") end

local passed, failed = 0, 0
function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("  ok   " .. name)
  else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
function eq(a, b, msg) if a ~= b then error((msg or "expected") .. ": " .. tostring(b) .. " got " .. tostring(a), 2) end end
function truthy(v, msg) if not v then error(msg or "expected truthy", 2) end end

for _, f in ipairs({ "tests/test_common.lua", "tests/test_pricing.lua", "tests/test_bank.lua", "tests/test_flows.lua" }) do
  print(f); dofile(f)
end
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
