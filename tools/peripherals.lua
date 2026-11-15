-- List everything on the computer's network: use it to find chest/barrel/monitor names for your config.
--   /craftbank/tools/peripherals.lua
for _, n in ipairs(peripheral.getNames()) do
  local t = { peripheral.getType(n) }
  print(n .. "  [" .. table.concat(t, ",") .. "]")
end
