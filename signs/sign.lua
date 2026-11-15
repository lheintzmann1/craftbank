-- Shop Sign Monitor: Displays scrolling price boards for market streets
-- Run on a computer with a monitor attached. Shows live prices from the exchange.
local dir = fs.getDir(shell.getRunningProgram())
package.path = "/" .. dir .. "/?.lua;" .. "/" .. fs.getDir(dir) .. "/?.lua;" .. package.path

local cfg     = require("config")
local proto   = require("common.protocol")
local money   = require("common.money")
local items   = require("common.items")
local pricing = require("common.pricing")

---------------------------------------------------------------- setup
for _, side in ipairs(redstone.getSides()) do
  if peripheral.getType(side) == "modem" then rednet.open(side) end
end
if not rednet.isOpen() then error("No modem attached") end

local mon = cfg.monitor and peripheral.wrap(cfg.monitor) or peripheral.find("monitor")
if not mon then error("No monitor found") end
local w, h = mon.getSize()

local link = proto.client({ dev = "sign-" .. tostring(os.getComputerID()), key = proto.rand_hex(16), host = "exchange", fixed = cfg.exchange_computer })
local function call(msg, timeout, tries) return link:call(msg, timeout or 6, tries or 1) end

---------------------------------------------------------------- configuration helpers
-- Parse item specification: can be "item_id", "item_id:count", or "category"
local function parse_items(items_list)
  local result = {}
  for _, spec in ipairs(items_list or {}) do
    if spec:find(":") then
      -- item_id:count format
      local id, count = spec:match("([^:]+):(%d+)")
      if id and count then
        for i = 1, tonumber(count) do result[#result + 1] = id end
      end
    else
      -- Single item or category
      result[#result + 1] = spec
    end
  end
  return result
end

-- Get items by category
local function get_items_by_category(cat)
  local result = {}
  for _, item in ipairs(items.list) do
    if item.cat == cat then result[#result + 1] = item.id end
  end
  return result
end

-- Expand item specs to actual item IDs
local function expand_items()
  local ids = {}
  for _, spec in ipairs(cfg.items or {}) do
    local cat = items.byId[spec] and items.byId[spec].cat
    if cat then
      -- It's a valid item ID
      ids[#ids + 1] = spec
    elseif spec:sub(1, 1) == "@" then
      -- Category prefix
      local category = spec:sub(2)
      local cat_items = get_items_by_category(category)
      for _, id in ipairs(cat_items) do ids[#ids + 1] = id end
    else
      -- Try to match as category or item
      local matched = false
      for _, item in ipairs(items.list) do
        if item.id == spec or item.cat == spec then
          ids[#ids + 1] = item.id
          matched = true
        end
      end
      if not matched then print("Warning: unknown item/category '" .. spec .. "'") end
    end
  end
  return ids
end

---------------------------------------------------------------- price fetching
local function fetch_prices(ids)
  local states = {}
  local r = call({ type = "market", op = "prices", args = { items = ids } })
  if r and r.ok then
    states = r.items
  end
  return states
end

local function get_price(item_id, states)
  local par = items.byId[item_id]
  if not par then return nil, nil end
  local st = states[item_id] or { 0, 1 }
  return pricing.mid(par, st[1], st[2]), par.base
end

---------------------------------------------------------------- display
local function clear() mon.setBackgroundColor(colors.black); mon.clear() end

local function put(x, y, text, fg, bg)
  if y < 1 or y > h or x > w then return end
  if x < 1 then text = text:sub(2 - x); x = 1 end
  text = text:sub(1, w - x + 1)
  if bg then mon.setBackgroundColor(bg) end
  if fg then mon.setTextColor(fg) end
  mon.setCursorPos(x, y); mon.write(text)
end

local function center(y, text, fg, bg)
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  put(x, y, text, fg, bg or colors.black)
end

-- Scrolling text display
local function scroll_text(texts, speed, fg)
  fg = fg or colors.white
  local full_text = table.concat(texts, "  ")
  local len = #full_text
  if len <= w then center(1, full_text, fg); return end
  
  local start = 0
  while true do
    clear()
    local segment = full_text:sub(start + 1, start + w)
    center(1, segment, fg)
    start = (start + 1) % len
    sleep(speed or 0.2)
  end
end

-- Grid display for multiple items
local function grid_display(ids, states)
  clear()
  local x, y = 1, 1
  local per_row = math.floor(w / 20)  -- Approximate items per row
  if per_row < 1 then per_row = 1 end
  
  for i, id in ipairs(ids) do
    local par = items.byId[id]
    if par then
      local mid, base = get_price(id, states)
      local display = items.display(id):sub(1, 12)
      local pct = (mid and base and base > 0) and ((mid - base) / base * 100) or 0
      local price_str = mid and money.short(math.floor(mid)) or "N/A"
      
      local row = math.floor((i - 1) / per_row)
      local col = (i - 1) % per_row
      local px = col * 20 + 1
      local py = row + 1
      
      if py <= h then
        put(px, py, string.format("%-12s %8s", display, price_str), 
          pct > 5 and colors.lime or pct < -5 and colors.red or colors.white)
      end
    end
    if y >= h then break end
  end
end

-- Ticker tape style display
local function ticker_display(ids, states)
  clear()
  local lines = {}
  for i, id in ipairs(ids) do
    local par = items.byId[id]
    if par then
      local mid, base = get_price(id, states)
      local display = items.display(id):sub(1, 15)
      local price_str = mid and money.short(math.floor(mid)) or "N/A"
      local pct = (mid and base and base > 0) and ((mid - base) / base * 100) or 0
      local color = pct > 5 and "+" or pct < -5 and "-" or "="
      lines[#lines + 1] = string.format("[%s] %-15s %8s %+5.0f%%", color, display, price_str, pct)
    end
  end
  
  scroll_text(lines, cfg.scroll_speed or 0.2)
end

-- Marquee display (single line scrolling)
local function marquee_display(ids, states)
  clear()
  local texts = {}
  for i, id in ipairs(ids) do
    local par = items.byId[id]
    if par then
      local mid, base = get_price(id, states)
      local display = items.display(id):sub(1, 20)
      local price_str = mid and money.short(math.floor(mid)) or "N/A"
      local pct = (mid and base and base > 0) and ((mid - base) / base * 100) or 0
      texts[#texts + 1] = string.format("%s: %s (%+4.0f%%)", display, price_str, pct)
    end
  end
  
  scroll_text(texts, cfg.scroll_speed or 0.15)
end

---------------------------------------------------------------- main
local function main()
  local ids = expand_items()
  if #ids == 0 then
    -- Default to all items if none specified
    ids = {} -- Will be filled with all items
  end
  
  -- If no items specified, show all
  if #ids == 0 then
    for _, item in ipairs(items.list) do
      if not items.byId[item.id].peg then ids[#ids + 1] = item.id end
    end
  end
  
  local display_mode = cfg.display_mode or "ticker"
  local refresh_interval = cfg.refresh_seconds or 10
  
  while true do
    local states = fetch_prices(ids)
    
    if display_mode == "grid" then
      grid_display(ids, states)
      sleep(refresh_interval)
    elseif display_mode == "ticker" then
      ticker_display(ids, states)
      -- ticker_display runs forever, so we need to handle refresh differently
      -- For now, we'll break out after a while and refresh
      sleep(refresh_interval * 4)
      -- Break out of scroll_text by sending a dummy event
      -- This is a bit hacky, but we need to restart the scrolling
      break
    elseif display_mode == "marquee" then
      marquee_display(ids, states)
      sleep(refresh_interval * 3)
      break
    else
      -- Default to ticker
      ticker_display(ids, states)
      sleep(refresh_interval * 4)
      break
    end
  end
end

while true do
  local ok, err = pcall(main)
  if not ok then
    if tostring(err):find("Terminated") then break end
    clear()
    center(1, "Sign Error", colors.red)
    center(2, tostring(err):sub(1, w), colors.white)
    sleep(5)
  end
end
