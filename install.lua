-- CraftBank installer.  On a CC computer:
--     wget run https://raw.githubusercontent.com/YOUR_USER/craftbank/main/install.lua <atm|shop|bank|exchange>
-- Re-run any time to update code; your config.lua is never overwritten.
local BASE = "https://raw.githubusercontent.com/lheintzmann1/craftbank/main/"   -- <-- edit after you push the repo
local ROOT = "/craftbank"

local role = ({ ... })[1]
local MAIN = { atm = "atm/atm.lua", shop = "shop/shop.lua", bank = "bank/server.lua", exchange = "exchange/server.lua" }
if not MAIN[role] then error("usage: install <atm|shop|bank|exchange>", 0) end

local files = {
  "common/const.lua", "common/money.lua", "common/serial.lua", "common/sha256.lua", "common/protocol.lua",
  "common/proc.lua", "common/storage.lua", "common/items.lua", "common/pricing.lua", "common/ui.lua",
  "common/inventory.lua", "data/base_prices.lua",
  MAIN[role], role .. "/config.example.lua",
}
if role == "bank" then files[#files + 1] = "bank/core.lua" end
if role == "exchange" then files[#files + 1] = "exchange/core.lua" end

local function get(path)
  local h = http.get(BASE .. path)
  if not h then error("download failed: " .. path, 0) end
  local s = h.readAll(); h.close(); return s
end

for _, f in ipairs(files) do
  write("  " .. f .. " ... ")
  local s = get(f)
  local out = fs.open(fs.combine(ROOT, f), "w"); out.write(s); out.close()
  print("ok")
end

local cfgfile = fs.combine(ROOT, role .. "/config.lua")
if not fs.exists(cfgfile) then
  fs.copy(fs.combine(ROOT, role .. "/config.example.lua"), cfgfile)
  print("\nCreated " .. cfgfile .. " - edit it before starting:  edit " .. cfgfile)
end

local startup = fs.open("/startup.lua", "w")
startup.write('shell.run("' .. fs.combine(ROOT, MAIN[role]) .. '")\n'); startup.close()
print("\nInstalled '" .. role .. "'. Reboot (or run /startup.lua) once config.lua is filled in.")
