-- Pocket-computer wallet: balance, generate pay code, transfer
-- Run on a pocket computer with a modem. Uses the terminal for UI.
local dir = fs.getDir(shell.getRunningProgram())
package.path = "/" .. dir .. "/?.lua;" .. "/" .. fs.getDir(dir) .. "/?.lua;" .. package.path

local cfg    = require("config")
local const  = require("common.const")
local money  = require("common.money")
local proto  = require("common.protocol")

---------------------------------------------------------------- setup
for _, side in ipairs(redstone.getSides()) do
  if peripheral.getType(side) == "modem" then rednet.open(side) end
end
if not rednet.isOpen() then error("No modem attached") end

local link = proto.client({ dev = cfg.device_id, key = cfg.device_key, host = "bank-" .. cfg.bank_no, fixed = cfg.bank_computer })
local function call(msg, tries) return link:call(msg, 6, tries or 1) end

local S = nil   -- current session { tok, acct, owner, bal }

local function fmt_acct(s) return #s > 2 and (s:sub(1, 2) .. "-" .. s:sub(3)) or s end
local function reason(r) if not r then return "Bank unreachable. Try later." end; return r.msg or r.err or "Error" end

---------------------------------------------------------------- helpers for terminal UI
local function clear() term.clear(); term.setCursorPos(1, 1) end
local function header(title) clear(); print(title); print(string.rep("-", #title)) end
local function center(text, y) 
  local w, h = term.getSize()
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  term.setCursorPos(x, y or math.floor(h / 2)) 
  print(text)
end

local function prompt(p, default)
  write(p .. (default and " [" .. default .. "]" or "") .. ": ")
  local s = read()
  return s == "" and default or s
end

local function yesno(p)
  while true do
    local s = prompt(p .. " (y/n)")
    s = s:lower()
    if s == "y" or s == "yes" then return true end
    if s == "n" or s == "no" then return false end
  end
end

local function passprompt(p)
  write(p .. ": ")
  local s = read("*")
  return s
end

---------------------------------------------------------------- session management
local function logout()
  if S then call({ type = "logout", tok = S.tok }); S = nil end
end

local function login()
  local acct = prompt("Account no", S and S.acct or nil)
  if not acct then return end
  local pin = passprompt("PIN")
  if not pin then return end
  print("Logging in...")
  local r = call({ type = "login", acct = acct, pin = pin })
  if r and r.ok then
    S = { tok = r.tok, acct = r.acct, owner = r.owner, bal = r.bal }
    print("Welcome, " .. r.owner)
    return true
  end
  printError("Login failed: " .. reason(r))
end

---------------------------------------------------------------- wallet functions
local function show_balance()
  header("Balance")
  print("Account: " .. S.acct)
  print("Owner:   " .. S.owner)
  print("Balance: " .. money.short(S.bal) .. " Cr")
  print("\nPress any key...")
  os.pullEvent("key")
end

local function gen_paycode()
  local max = prompt("Max amount (Cr)")
  if not max then return end
  local mx = tonumber(max) and tonumber(max) * const.SCALE
  if not mx or mx < 1 then return printError("Invalid amount") end
  print("Generating pay code...")
  local r = call({ type = "gen_code", tok = S.tok, max = mx })
  if r and r.ok then
    header("Pay Code")
    print("Code: " .. r.code:sub(1, 2) .. " " .. r.code:sub(3))
    print("Max:  " .. money.short(mx) .. " Cr")
    print("Valid for " .. (r.ttl or 600) .. " seconds")
    print("\nEnter this code at any shop.")
    print("\nPress any key...")
    os.pullEvent("key")
  else
    printError("Failed: " .. reason(r))
  end
end

local function do_transfer()
  local to = prompt("To account")
  if not to then return end
  local r = call({ type = "lookup", acct = to }, 2)
  if not (r and r.ok) then return printError("Account not found: " .. reason(r)) end
  local amt_str = prompt("Amount (Cr)")
  if not amt_str then return end
  local amt = tonumber(amt_str) and tonumber(amt_str) * const.SCALE
  if not amt or amt < 1 then return printError("Invalid amount") end
  if not yesno("Send " .. money.short(amt) .. " Cr to " .. r.name .. "?") then return end
  print("Transferring...")
  local r2 = call({ type = "transfer", tok = S.tok, to = to, amount = amt, ref = proto.rand_hex(10) }, 3)
  if r2 and r2.ok then
    S.bal = r2.bal
    print("Sent " .. money.short(amt) .. " Cr")
    print("Fee: " .. money.short(r2.fee or 0) .. " Cr")
    print("New balance: " .. money.short(S.bal) .. " Cr")
    print("\nPress any key...")
    os.pullEvent("key")
  else
    printError("Failed: " .. reason(r2))
  end
end

local function show_history()
  header("Transaction History")
  print("Fetching...")
  local r = call({ type = "history", tok = S.tok })
  if not (r and r.ok) then return printError("Failed: " .. reason(r)) end
  S.bal = r.bal
  if #r.hist == 0 then print("No transactions yet") end
  local KIND = { dep = "Deposit", wd = "Withdraw", xfer = "Sent", xfer_in = "Received",
    shop = "Shop", shop_in = "Sale", fee = "Fee", refund = "Refund", admin = "Bank" }
  for _, h in ipairs(r.hist) do
    local sign = h.amt >= 0 and "+" or ""
    print(string.format("%-12s %s%s Cr", KIND[h.k] or h.k, sign, money.short(h.amt)))
  end
  print("\nCurrent balance: " .. money.short(S.bal) .. " Cr")
  print("\nPress any key...")
  os.pullEvent("key")
end

---------------------------------------------------------------- main menu
local function main_menu()
  while true do
    clear()
    print("Pocket Wallet")
    print(string.rep("-", 12))
    print("1. View balance")
    print("2. Generate pay code")
    print("3. Transfer")
    print("4. History")
    print("5. Log out")
    if not S then print("6. Log in") end
    print("0. Exit")
    write("\nChoose: ")
    local choice = read()
    if not S and choice ~= "6" and choice ~= "0" then
      printError("Please log in first")
      sleep(1)
      choice = "6"
    end
    if choice == "1" then show_balance()
    elseif choice == "2" then gen_paycode()
    elseif choice == "3" then do_transfer()
    elseif choice == "4" then show_history()
    elseif choice == "5" or choice == "6" then
      logout()
      if choice == "6" then login() end
    elseif choice == "0" then break end
  end
end

---------------------------------------------------------------- main
local function main()
  while true do
    main_menu()
    logout()
  end
end

while true do
  local ok, err = pcall(main)
  if not ok then
    if tostring(err):find("Terminated") then break end
    S = nil
    printError("Error: " .. tostring(err))
    sleep(2)
  end
end
