-- Discord webhook notifications for CraftBank
-- Sends formatted messages to a Discord channel via webhook URL
local M = {}

local function send_discord(url, payload)
  if not url or not http then return false end
  
  local ok, err = pcall(function()
    local body = textutils.serialiseJSON(payload)
    local headers = { ["Content-Type"] = "application/json", ["Content-Length"] = tostring(#body) }
    local response = http.post(url, body, headers)
    if response then
      response.readAll()
      response.close()
      return true
    end
    return false
  end)
  
  return ok and true or false
end

-- Send a formatted message to Discord
-- @param url: webhook URL
-- @param title: message title/embedding title
-- @param description: main message content
-- @param color: hex color (optional, default: 0x00ff00 green)
-- @param fields: array of { name, value, inline } (optional)
-- @param username: override webhook username (optional)
function M.notify(url, title, description, color, fields, username)
  if not url then return false end
  
  local embed = {
    title = title or "",
    description = description or "",
    color = color or 0x00ff00,
    timestamp = os.epoch and os.epoch("utc") or os.time() * 1000,
    fields = fields or {}
  }
  
  local payload = {
    username = username or "CraftBank",
    embeds = { embed }
  }
  
  return send_discord(url, payload)
end

-- Send a simple text message (no embed)
function M.simple(url, content, username)
  if not url then return false end
  local payload = {
    content = content,
    username = username or "CraftBank"
  }
  return send_discord(url, payload)
end

-- Format amount in Cr
local function fmt_cr(amount)
  if not amount then return "N/A" end
  if amount >= 100000 then
    return string.format("%.1fK Cr", amount / 1000)
  elseif amount >= 1000 then
    return string.format("%.1fK Cr", amount / 1000)
  else
    return amount .. " Cr"
  end
end

-- Notify about a big transfer
function M.notify_transfer(url, from, to, amount, fee, bank_name)
  if not url then return false end
  local fields = {
    { name = "From", value = from or "Unknown", inline = true },
    { name = "To", value = to or "Unknown", inline = true },
    { name = "Amount", value = fmt_cr(amount), inline = true },
    { name = "Fee", value = fmt_cr(fee or 0), inline = true },
    { name = "Bank", value = bank_name or "Unknown", inline = false }
  }
  return M.notify(url, "\u{1F4B0} Big Transfer", "A large transfer was processed", 0x0000ff, fields, "CraftBank | Transfers")
end

-- Notify about bank alert (pending, limit reached, etc.)
function M.notify_alert(url, alert_type, message, bank_no, bank_name)
  if not url then return false end
  local color = 0xff0000  -- red
  local emoji = "\u{1F514}"  -- bell
  if alert_type == "pending" then
    emoji = "\u{23F0}"  -- alarm clock
  elseif alert_type == "limit" then
    emoji = "\u{1F534}"  -- red circle
  end
  return M.notify(url, emoji .. " Bank Alert: " .. (alert_type or "Unknown"), message or "", color, 
    { { name = "Bank", value = (bank_name or "") .. " (#" .. (bank_no or "?") .. ")", inline = false } },
    "CraftBank | Alerts")
end

-- Notify about market news/event
function M.notify_event(url, event_text, multiplier, duration_min)
  if not url then return false end
  local color = multiplier > 1 and 0xff0000 or 0x00ff00  -- red for negative events, green for positive
  local emoji = multiplier > 1 and "\u{1F4C8}" or "\u{1F4C9}"  -- chart up/down
  return M.notify(url, emoji .. " Market Event", event_text .. " (x" .. (multiplier or 1) .. ")", color,
    { { name = "Duration", value = duration_min .. " minutes", inline = true } },
    "CraftBank | Market")
end

return M
