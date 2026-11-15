-- Inventory helpers for the "one chest in front, vault behind the wall" design.
-- All inventories are reached through a wired-modem network, so they are addressed by network name
-- (e.g. "minecraft:chest_0", "minecraft:barrel_3"); items are moved with pushItems().
local M = {}
local call = peripheral.call

-- stack sizes: default 64; a few exceptions (good enough for capacity checks)
local ONE = { "_sword", "_pickaxe", "_axe", "_shovel", "_hoe", "_helmet", "_chestplate", "_leggings", "_boots",
  "elytra", "totem_of_undying", "saddle", "shield", "bow", "minecart", "_boat", "shulker_box", "_horse_armor",
  "trident", "fishing_rod", "shears", "flint_and_steel", "compass", "clock", "spyglass" }
local SIXTEEN = { ender_pearl = 1, egg = 1, snowball = 1, bucket = 1, honey_bottle = 1, name_tag = 1, experience_bottle = 0,
  ["netherite_upgrade_smithing_template"] = 0 }
function M.stack_size(id)
  local short = id:gsub("^[%w_]+:", "")
  if SIXTEEN[short] == 1 then return 16 end
  for _, suffix in ipairs(ONE) do
    if short == suffix or short:sub(-#suffix) == suffix then return 1 end
  end
  return 64
end

-- names of attached inventories whose network name contains `pattern` (e.g. "chest", "barrel")
function M.names(pattern)
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if n:find(pattern, 1, true) then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

local function slots(name)
  local list = call(name, "list") or {}
  local keys = {}
  for s in pairs(list) do keys[#keys + 1] = s end
  table.sort(keys)
  return list, keys
end

-- { [item id] = count } over several inventories. plain=true ignores stacks with NBT (enchanted, damaged, named...)
function M.tally(names, plain)
  local t = {}
  for _, n in ipairs(names) do
    local list = call(n, "list") or {}
    for _, st in pairs(list) do
      if not (plain and st.nbt) then t[st.name] = (t[st.name] or 0) + st.count end
    end
  end
  return t
end

function M.count(names, id)
  local c = 0
  for _, n in ipairs(names) do
    for _, st in pairs(call(n, "list") or {}) do if st.name == id and not st.nbt then c = c + st.count end end
  end
  return c
end

-- Move up to qty of `id` from inventory `from` into any of `tos`. Returns number moved.
function M.move(from, tos, id, qty)
  local moved = 0
  local list, keys = slots(from)
  for _, slot in ipairs(keys) do
    local st = list[slot]
    if moved >= qty then break end
    if st.name == id and not st.nbt then
      local want = math.min(st.count, qty - moved)
      for _, to in ipairs(tos) do
        if want <= 0 then break end
        local n = call(from, "pushItems", to, slot, want) or 0
        moved, want = moved + n, want - n
      end
    end
  end
  return moved
end

-- Move every stack for which pred(stack) is true. Returns { [id] = count }.
function M.move_where(from, tos, pred)
  local moved = {}
  local list, keys = slots(from)
  for _, slot in ipairs(keys) do
    local st = list[slot]
    if pred(st) then
      local want = st.count
      for _, to in ipairs(tos) do
        if want <= 0 then break end
        local n = call(from, "pushItems", to, slot, want) or 0
        if n > 0 then moved[st.name] = (moved[st.name] or 0) + n; want = want - n end
      end
    end
  end
  return moved
end

-- How many more of `id` fit into inventory `name`?
function M.free_space(name, id)
  local stack = M.stack_size(id)
  local size = call(name, "size")
  local list = call(name, "list") or {}
  local used, free = 0, 0
  for _, st in pairs(list) do
    used = used + 1
    if st.name == id and not st.nbt then free = free + math.max(0, stack - st.count) end
  end
  return free + (size - used) * stack
end

-- true if the inventory has no items at all
function M.is_empty(name) return next(call(name, "list") or {}) == nil end

return M
