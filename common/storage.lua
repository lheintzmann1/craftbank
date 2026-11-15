-- Crash-safe persistence for CC computers (atomic write via tmp file + move).
local serial = require("common.serial")
local M = {}

local function readfile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close(); return s
end

local function writefile(path, s)
  local tmp = path .. ".tmp"
  local f = fs.open(tmp, "w"); f.write(s); f.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
end

-- Open (or create) a database file. Returns { data = <table>, save = function }.
function M.open(path, default)
  local db = { path = path, saves = 0 }
  local raw = readfile(path) or readfile(path .. ".bak")
  db.data = raw and serial.decode(raw) or default or {}
  function db.save()
    db.saves = db.saves + 1
    if db.saves % 25 == 0 and fs.exists(path) then fs.copy(path, path .. ".bak") end
    writefile(path, serial.encode(db.data))
  end
  return db
end

-- Append one line to a log file, rotating at ~150 KB.
function M.append(path, line)
  if fs.exists(path) and fs.getSize(path) > 150000 then
    local old = path .. ".1"
    if fs.exists(old) then fs.delete(old) end
    fs.move(path, old)
  end
  local f = fs.open(path, "a"); f.writeLine(line); f.close()
end

return M
