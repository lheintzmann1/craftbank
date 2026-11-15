-- Touch UI toolkit for monitors (also works on a normal terminal with mouse clicks).
-- Everything is laid out relative to the real screen size, so it works from a 1x1 monitor
-- (15x10 characters at text scale 0.5) up to big walls.
local UI = {}
UI.__index = UI

function UI.new(t, side)
  local self = setmetatable({ t = t, side = side, btns = {} }, UI)
  self.w, self.h = t.getSize()
  self.c = { bg = colors.black, fg = colors.white, head = colors.blue, ok = colors.green, bad = colors.red,
    warn = colors.orange, dim = colors.lightGray, btn = colors.gray, accent = colors.yellow }
  return self
end

local function wrap(s, w)
  local lines = {}
  for para in (tostring(s) .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      if line ~= "" and #line + #word + 1 > w then lines[#lines + 1] = line; line = word
      else line = (line == "") and word or (line .. " " .. word) end
    end
    lines[#lines + 1] = line
  end
  return lines
end
UI.wrap = wrap

---------------------------------------------------------------- drawing primitives
function UI:clear()
  local t = self.t
  t.setBackgroundColor(self.c.bg); t.setTextColor(self.c.fg); t.clear(); t.setCursorPos(1, 1)
  self.btns = {}
end

function UI:put(x, y, s, fg, bg)
  if y < 1 or y > self.h or x > self.w then return end
  if x < 1 then s = s:sub(2 - x); x = 1 end
  s = s:sub(1, self.w - x + 1)
  local t = self.t
  if bg then t.setBackgroundColor(bg) end
  if fg then t.setTextColor(fg) end
  t.setCursorPos(x, y); t.write(s)
end

function UI:fill(x, y, w, h, bg)
  for j = y, y + h - 1 do self:put(x, j, string.rep(" ", w), nil, bg) end
end

function UI:center(y, s, fg, bg, x0, w)
  x0, w = x0 or 1, w or self.w
  s = s:sub(1, w)
  self:put(x0 + math.floor((w - #s) / 2), y, s, fg or self.c.fg, bg or self.c.bg)
end

function UI:region(id, x, y, w, h) self.btns[#self.btns + 1] = { id = id, x = x, y = y, w = w, h = h } end

function UI:button(id, x, y, w, h, label, bg, fg)
  bg, fg = bg or self.c.btn, fg or colors.white
  self:fill(x, y, w, h, bg)
  local lines = type(label) == "table" and label or { label }
  local ly = y + math.floor((h - #lines) / 2)
  for i, l in ipairs(lines) do self:center(ly + i - 1, l, fg, bg, x, w) end
  self:region(id, x, y, w, h)
end

function UI:header(title, back, color)
  color = color or self.c.head
  self:fill(1, 1, self.w, 1, color)
  if back then self:button("back", 1, 1, 3, 1, "<", self.c.bad) end
  local x0 = back and 4 or 1
  self:center(1, title, colors.white, color, x0, self.w - x0 + 1)
end

---------------------------------------------------------------- input
function UI:hit(x, y)
  for i = #self.btns, 1, -1 do
    local b = self.btns[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b.id end
  end
end

-- Wait for a tap on a registered button. Returns id, or nil,"timeout".
function UI:wait(timeout)
  local timer = timeout and os.startTimer(timeout)
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "monitor_touch" and (not self.side or a == self.side) or ev == "mouse_click" then
      local id = self:hit(b, c)
      if id ~= nil then if timer then os.cancelTimer(timer) end; return id end
    elseif ev == "timer" and a == timer then return nil, "timeout" end
  end
end

---------------------------------------------------------------- screens
function UI:splash(title, line)
  self:clear(); self:header(title)
  for i, l in ipairs(wrap(line or "Please wait...", self.w)) do self:center(2 + i, l, self.c.dim) end
end

-- items = { {id=, label=, bg=} ... }  opts = { back=, sub=, timeout=, color= }
function UI:menu(title, items, opts)
  opts = opts or {}
  self:clear(); self:header(title, opts.back, opts.color)
  local top = 2
  if opts.sub then self:center(2, opts.sub, self.c.accent); top = 3 end
  local n = #items
  local bh = math.max(1, math.floor((self.h - top + 1) / n))
  local gap = bh >= 3 and 1 or 0
  for i, it in ipairs(items) do
    self:button(it.id, 1, top + (i - 1) * bh, self.w, bh - gap, it.label, it.bg)
  end
  return self:wait(opts.timeout)
end

-- Numeric keypad. o = { maxlen=, masked=, hint=, fmt=fn(str)->str, minlen=, timeout=, initial= }
-- returns digits string, or nil,"back"/"timeout"
function UI:keypad(title, o)
  o = o or {}
  local s = o.initial or ""
  local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "<", "0", "OK" }
  local kh, kw = math.max(1, math.floor((self.h - 2) / 4)), math.floor(self.w / 3)
  while true do
    self:clear(); self:header(title, true)
    self:fill(1, 2, self.w, 1, colors.black)
    if s == "" and o.hint then self:put(1, 2, o.hint, self.c.dim, colors.black)
    else
      local shown = o.masked and string.rep("*", #s) or (o.fmt and o.fmt(s) or s)
      self:put(math.max(1, self.w - #shown), 2, shown, self.c.accent, colors.black)
    end
    for r = 0, 3 do for c = 0, 2 do
      local k = keys[r * 3 + c + 1]
      local bg = (k == "OK") and self.c.ok or (k == "<") and self.c.warn or (((r + c) % 2 == 0) and colors.gray or colors.lightGray)
      local fg = (bg == colors.lightGray) and colors.black or colors.white
      self:button(k, c * kw + 1, 3 + r * kh, kw, kh, k, bg, fg)
    end end
    local id, why = self:wait(o.timeout)
    if not id then return nil, why end
    if id == "back" then return nil, "back"
    elseif id == "<" then s = s:sub(1, -2)
    elseif id == "OK" then if #s >= (o.minlen or 1) then return s end
    elseif #s < (o.maxlen or 8) then s = s .. id end
  end
end

-- lines: string or {strings}; kind: "ok" | "bad" | nil.   Taps anywhere to dismiss.
function UI:message(title, lines, kind, timeout)
  self:clear()
  self:header(title, false, kind == "ok" and self.c.ok or kind == "bad" and self.c.bad or self.c.head)
  local y = 3
  for _, l in ipairs(type(lines) == "table" and lines or { lines }) do
    for _, wl in ipairs(wrap(l, self.w)) do self:center(y, wl); y = y + 1 end
  end
  self:center(self.h, "- tap -", self.c.dim)
  self:region("x", 1, 1, self.w, self.h)
  return self:wait(timeout or 30)
end

-- returns true / false(no or back) / nil(timeout)
function UI:confirm(title, lines, yes, no)
  self:clear(); self:header(title)
  local y = 2
  for _, l in ipairs(type(lines) == "table" and lines or { lines }) do
    for _, wl in ipairs(wrap(l, self.w)) do self:center(y, wl); y = y + 1 end
  end
  local bh = math.max(1, math.min(3, self.h - y))
  local by = self.h - bh + 1
  local hw = math.floor(self.w / 2)
  self:button("no", 1, by, hw, bh, no or "No", self.c.bad)
  self:button("yes", hw + 1, by, self.w - hw, bh, yes or "OK", self.c.ok)
  local id, why = self:wait(45)
  if not id then return nil, why end
  return id == "yes"
end

-- Scrollable list. rows = { {id=, l=left text, r=right text, fg=} }  o = { back=true, per=, timeout= }
-- Rows without id are display-only. Returns selected id, "back", or nil on timeout.
function UI:list(title, rows, o)
  o = o or {}
  local per = self.h - 2
  local pages = math.max(1, math.ceil(#rows / per))
  local page = 1
  while true do
    self:clear(); self:header(title, o.back ~= false)
    for i = 1, per do
      local r = rows[(page - 1) * per + i]
      if r then
        local y = 1 + i
        local bg = (i % 2 == 0) and colors.gray or colors.black
        self:fill(1, y, self.w, 1, bg)
        local right = r.r or ""
        local left = (r.l or ""):sub(1, self.w - #right - 1)
        self:put(1, y, left, r.fg or colors.white, bg)
        self:put(self.w - #right + 1, y, right, r.rfg or colors.yellow, bg)
        if r.id ~= nil then self:region(r.id, 1, y, self.w, 1) end
      end
    end
    if pages > 1 then
      self:button("prev", 1, self.h, 3, 1, "<", colors.gray)
      self:center(self.h, page .. "/" .. pages, self.c.dim, nil, 4, self.w - 6)
      self:button("next", self.w - 2, self.h, 3, 1, ">", colors.gray)
    end
    local id, why = self:wait(o.timeout or 45)
    if not id then return nil, why end
    if id == "back" then return "back"
    elseif id == "prev" then page = page > 1 and page - 1 or pages
    elseif id == "next" then page = page < pages and page + 1 or 1
    else return id end
  end
end

-- Quantity picker. o = { name=, line=, min=1, max=, qty=, total=fn(q)->string }
function UI:stepper(title, o)
  local lo, hi = o.min or 1, o.max
  local q = math.max(lo, math.min(hi, o.qty or lo))
  while true do
    self:clear(); self:header(title, true)
    self:center(2, o.name, self.c.accent)
    if o.line then self:center(3, o.line, self.c.dim) end
    self:center(4, "Qty " .. q .. "/" .. hi)
    self:center(5, o.total(q), self.c.ok)
    local avail = self.h - 5
    local ha = math.max(1, math.floor(avail / 2)); local hb = math.max(1, avail - ha)
    local qw = math.floor(self.w / 4)
    local defs = { { "-10", -10, self.c.bad }, { "-1", -1, self.c.warn }, { "+1", 1, colors.green }, { "+10", 10, colors.lime } }
    for i, d in ipairs(defs) do
      self:button(d[2], (i - 1) * qw + 1, 6, i == 4 and (self.w - 3 * qw) or qw, ha, d[1], d[3], i == 4 and colors.black or colors.white)
    end
    local hw = math.floor(self.w / 3)
    self:button("max", 1, 6 + ha, hw, hb, "MAX", colors.gray)
    self:button("ok", hw + 1, 6 + ha, self.w - hw, hb, "OK", self.c.ok)
    local id, why = self:wait(45)
    if not id then return nil, why end
    if id == "back" then return nil, "back"
    elseif id == "ok" then return q
    elseif id == "max" then q = hi
    else q = math.max(lo, math.min(hi, q + id)) end
  end
end

-- On-screen keyboard. o = { maxlen=, initial= } -> string or nil
function UI:keyboard(title, o)
  o = o or {}
  local s = o.initial or ""
  local rows = { "1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }
  local kw = math.max(1, math.floor(self.w / 10))
  local rh = math.max(1, math.floor((self.h - 4) / 4))
  local bottom_h = math.max(1, self.h - 2 - 4 * rh)
  while true do
    self:clear(); self:header(title, true)
    self:fill(1, 2, self.w, 1, colors.black)
    local shown = s:sub(-(self.w - 1))
    self:put(1, 2, shown .. "_", self.c.accent, colors.black)
    for r, row in ipairs(rows) do
      local x0 = 1 + math.floor((self.w - #row * kw) / 2)
      for i = 1, #row do
        local ch = row:sub(i, i)
        local light = (i + r) % 2 == 0
        self:button(ch, x0 + (i - 1) * kw, 2 + (r - 1) * rh + 1, kw, rh, ch, light and colors.lightGray or colors.gray, light and colors.black or colors.white)
      end
    end
    local by, w3 = 3 + 4 * rh, math.floor(self.w / 3)
    self:button("_space", 1, by, w3, bottom_h, "SPC", colors.gray)
    self:button("_del", w3 + 1, by, w3, bottom_h, "DEL", self.c.warn)
    self:button("_ok", 2 * w3 + 1, by, self.w - 2 * w3, bottom_h, "OK", self.c.ok)
    local id, why = self:wait(60)
    if not id then return nil, why end
    if id == "back" then return nil, "back"
    elseif id == "_del" then s = s:sub(1, -2)
    elseif id == "_ok" then if #s > 0 then return s end
    elseif #s < (o.maxlen or 16) then
      if id == "_space" then s = s .. " "
      else
        local prev = s:sub(-1)
        s = s .. ((s == "" or prev == " ") and id or id:lower())   -- auto-capitalise words
      end
    end
  end
end

return UI
