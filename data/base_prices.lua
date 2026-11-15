-- BASE PRICES (in Cr, where 1 diamond = 1000 Cr)
--
-- Philosophy:
--   * raw materials are priced by scarcity/effort (diamond is the unit of account, pegged)
--   * everything crafted/smelted is DERIVED from its ingredients, so the table stays consistent
--     (price = sum(ingredients) / output * markup)
-- These are only the *reference* prices. The live market price moves around them (see common/pricing.lua).
--
-- Add or tweak items freely, but every node (exchange, bank, shops) must run the same file.
-- A checksum is exchanged on the network so mismatches are detected.

local list, byId = {}, {}

local function add(cat, id, price, extra)
  local e = { id = "minecraft:" .. id, cat = cat, base = math.max(1, math.floor(price * 100 + 0.5)) }
  if extra then for k, v in pairs(extra) do e[k] = v end end
  assert(not byId[e.id], "duplicate item " .. id)
  list[#list + 1] = e; byId[e.id] = e
end

local function raw(cat, items)
  for _, it in ipairs(items) do add(cat, it[1], it[2], it[3]) end
end

-- price from a recipe: ing = { item = count, ... }
local function craft(cat, id, ing, o)
  o = o or {}
  local sum = 0
  for name, n in pairs(ing) do
    local e = byId["minecraft:" .. name]
    assert(e, "unknown ingredient '" .. name .. "' for " .. id)
    sum = sum + e.base * n
  end
  add(cat, id, sum / (o.out or 1) * (o.markup or 1.05) / 100, o.peg and { peg = true } or nil)
end

local function compact(cat, block, item, n, extra) -- storage blocks: no crafting premium
  craft(cat, block, { [item] = n or 9 }, { markup = 1.0, peg = extra and extra.peg })
end

---------------------------------------------------------------- ORES, METALS, GEMS
raw("ore", {
  { "coal", 12 }, { "charcoal", 10 }, { "flint", 1.5 },
  { "raw_copper", 7 }, { "copper_ingot", 9 },
  { "raw_iron", 34 }, { "iron_ingot", 40 }, { "iron_nugget", 4.4 },
  { "raw_gold", 68 }, { "gold_ingot", 80 }, { "gold_nugget", 9 },
  { "redstone", 10 }, { "lapis_lazuli", 12 }, { "quartz", 18 }, { "amethyst_shard", 20 },
  { "emerald", 300 },
  { "diamond", 1000, { peg = true } },          -- THE unit of account
  { "netherite_scrap", 1500 }, { "echo_shard", 600 },
  { "glowstone_dust", 14 }, { "prismarine_shard", 25 }, { "prismarine_crystals", 40 },
})
craft("ore", "netherite_ingot", { netherite_scrap = 4, gold_ingot = 4 }, { markup = 1.0 })
compact("ore", "iron_block", "iron_ingot"); compact("ore", "gold_block", "gold_ingot")
compact("ore", "copper_block", "copper_ingot"); compact("ore", "coal_block", "coal")
compact("ore", "redstone_block", "redstone"); compact("ore", "lapis_block", "lapis_lazuli")
compact("ore", "emerald_block", "emerald"); compact("ore", "netherite_block", "netherite_ingot")
compact("ore", "diamond_block", "diamond", 9, { peg = true })
compact("ore", "quartz_block", "quartz", 4); compact("ore", "amethyst_block", "amethyst_shard", 4)
compact("ore", "glowstone", "glowstone_dust", 4)

---------------------------------------------------------------- WOOD
local woods = { "oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry" }
for _, w in ipairs(woods) do
  add("wood", w .. "_log", 6)
  craft("wood", w .. "_planks", { [w .. "_log"] = 1 }, { out = 4, markup = 1.0 })
end
for _, w in ipairs({ "oak", "spruce", "birch", "jungle", "acacia", "dark_oak" }) do add("wood", w .. "_sapling", 3) end
craft("wood", "stick", { oak_planks = 2 }, { out = 4 })

---------------------------------------------------------------- STONE / BUILDING
raw("stone", {
  { "cobblestone", 1 }, { "stone", 2 }, { "andesite", 1.5 }, { "diorite", 1.5 }, { "granite", 1.5 },
  { "deepslate", 1.5 }, { "cobbled_deepslate", 1 }, { "tuff", 1 }, { "calcite", 3 }, { "dripstone_block", 2 },
  { "dirt", 0.5 }, { "grass_block", 1 }, { "mud", 1 }, { "moss_block", 8 },
  { "sand", 1.5 }, { "red_sand", 2 }, { "gravel", 1.5 }, { "clay_ball", 3 }, { "brick", 4 }, { "glass", 3 },
  { "ice", 3 }, { "snowball", 1 }, { "obsidian", 20 }, { "crying_obsidian", 55 }, { "terracotta", 4 },
})
craft("stone", "stone_bricks", { stone = 4 }, { out = 4 })
craft("stone", "bricks", { brick = 4 }, { markup = 1.0 })
craft("stone", "sandstone", { sand = 4 }, { markup = 1.0 })
craft("stone", "glass_pane", { glass = 6 }, { out = 16, markup = 1.0 })
craft("stone", "glass_bottle", { glass = 3 }, { out = 3 })
craft("stone", "packed_ice", { ice = 9 }, { markup = 1.0 })
craft("stone", "blue_ice", { packed_ice = 9 }, { markup = 1.0 })
craft("stone", "snow_block", { snowball = 4 }, { markup = 1.0 })
craft("stone", "stone_pressure_plate", { stone = 2 })
craft("stone", "furnace", { cobblestone = 8 })

---------------------------------------------------------------- NETHER & END
raw("nether", {
  { "netherrack", 0.5 }, { "nether_brick", 2 }, { "soul_sand", 3 }, { "soul_soil", 3 }, { "basalt", 1.5 },
  { "blackstone", 1.5 }, { "magma_block", 12 }, { "blaze_rod", 90 }, { "ghast_tear", 250 }, { "nether_wart", 6 },
  { "shroomlight", 8 }, { "magma_cream", 35 }, { "wither_skeleton_skull", 2500 }, { "nether_star", 7000 },
})
craft("nether", "nether_bricks", { nether_brick = 4 }, { markup = 1.0 })
craft("nether", "blaze_powder", { blaze_rod = 1 }, { out = 2, markup = 1.0 })
raw("end", {
  { "end_stone", 2 }, { "chorus_fruit", 10 }, { "ender_pearl", 120 }, { "dragon_breath", 150 },
  { "shulker_shell", 500 }, { "elytra", 15000 }, { "dragon_egg", 50000 },
})
craft("end", "ender_eye", { ender_pearl = 1, blaze_powder = 1 })

---------------------------------------------------------------- MOB DROPS & LOOT
raw("mob", {
  { "bone", 4 }, { "string", 5 }, { "spider_eye", 6 }, { "gunpowder", 12 }, { "rotten_flesh", 1 },
  { "slime_ball", 30 }, { "feather", 3 }, { "leather", 10 }, { "rabbit_hide", 4 }, { "rabbit_foot", 70 },
  { "phantom_membrane", 90 }, { "ink_sac", 8 }, { "glow_ink_sac", 40 }, { "honeycomb", 40 },
  { "honey_bottle", 30 }, { "egg", 2 }, { "scute", 120 }, { "white_wool", 8 },
  { "sponge", 120 }, { "nautilus_shell", 250 }, { "heart_of_the_sea", 1500 }, { "totem_of_undying", 1800 },
  { "trident", 3500 }, { "enchanted_golden_apple", 6000 }, { "netherite_upgrade_smithing_template", 1500 },
  { "name_tag", 150 }, { "saddle", 400 }, { "experience_bottle", 90 },
  { "iron_horse_armor", 600 }, { "golden_horse_armor", 1000 }, { "diamond_horse_armor", 4500 },
})
craft("mob", "bone_meal", { bone = 1 }, { out = 3, markup = 1.0 })
compact("mob", "slime_block", "slime_ball")

---------------------------------------------------------------- FARMING & FOOD
raw("farm", {
  { "wheat", 2 }, { "wheat_seeds", 0.5 }, { "carrot", 2 }, { "potato", 2 }, { "beetroot", 2 },
  { "beetroot_seeds", 0.5 }, { "melon_slice", 1 }, { "pumpkin", 4 }, { "sugar_cane", 2 }, { "apple", 8 },
  { "sweet_berries", 3 }, { "glow_berries", 5 }, { "cocoa_beans", 6 }, { "kelp", 1 }, { "bamboo", 1 },
  { "cactus", 3 }, { "brown_mushroom", 4 }, { "red_mushroom", 4 }, { "lily_pad", 3 }, { "vine", 3 },
})
compact("farm", "hay_block", "wheat"); compact("farm", "melon", "melon_slice")
raw("food", {
  { "beef", 10 }, { "porkchop", 10 }, { "chicken", 8 }, { "mutton", 9 }, { "rabbit", 8 },
  { "cod", 5 }, { "salmon", 6 }, { "tropical_fish", 20 }, { "pufferfish", 25 },
})
craft("food", "cooked_beef", { beef = 1 }, { markup = 1.4 }); craft("food", "cooked_porkchop", { porkchop = 1 }, { markup = 1.4 })
craft("food", "cooked_chicken", { chicken = 1 }, { markup = 1.4 }); craft("food", "cooked_mutton", { mutton = 1 }, { markup = 1.4 })
craft("food", "cooked_rabbit", { rabbit = 1 }, { markup = 1.4 }); craft("food", "cooked_cod", { cod = 1 }, { markup = 1.4 })
craft("food", "cooked_salmon", { salmon = 1 }, { markup = 1.4 })
craft("food", "bread", { wheat = 3 }); craft("food", "baked_potato", { potato = 1 }, { markup = 1.3 })
craft("food", "dried_kelp", { kelp = 1 }, { markup = 1.3 })
craft("food", "sugar", { sugar_cane = 1 }, { markup = 1.0 })
craft("food", "paper", { sugar_cane = 3 }, { out = 3, markup = 1.0 })
craft("food", "cookie", { wheat = 2, cocoa_beans = 1 }, { out = 8 })
craft("food", "pumpkin_pie", { pumpkin = 1, sugar = 1, egg = 1 })
craft("food", "golden_carrot", { carrot = 1, gold_nugget = 8 })
craft("food", "golden_apple", { apple = 1, gold_ingot = 8 })

---------------------------------------------------------------- DYES
for _, d in ipairs({ "red", "orange", "yellow", "lime", "green", "cyan", "light_blue", "blue", "purple",
  "magenta", "pink", "white", "light_gray", "gray", "black", "brown" }) do add("dye", d .. "_dye", 4) end

---------------------------------------------------------------- REDSTONE
craft("redstone", "redstone_torch", { redstone = 1, stick = 1 })
craft("redstone", "repeater", { redstone = 1, redstone_torch = 2, stone = 3 })
craft("redstone", "comparator", { redstone_torch = 3, quartz = 1, stone = 3 })
craft("misc", "chest", { oak_planks = 8 })
craft("redstone", "piston", { oak_planks = 3, cobblestone = 4, iron_ingot = 1, redstone = 1 })
craft("redstone", "sticky_piston", { piston = 1, slime_ball = 1 })
craft("redstone", "observer", { cobblestone = 6, redstone = 2, quartz = 1 })
craft("redstone", "hopper", { iron_ingot = 5, chest = 1 })
craft("redstone", "dropper", { cobblestone = 7, redstone = 1 })
craft("redstone", "bow", { stick = 3, string = 3 })
craft("redstone", "dispenser", { dropper = 1, bow = 1 })
craft("redstone", "tnt", { gunpowder = 5, sand = 4 })
craft("redstone", "rail", { iron_ingot = 6, stick = 1 }, { out = 16 })
craft("redstone", "powered_rail", { gold_ingot = 6, stick = 1, redstone = 1 }, { out = 6 })
craft("redstone", "detector_rail", { iron_ingot = 6, stone_pressure_plate = 1, redstone = 1 }, { out = 6 })
craft("redstone", "redstone_lamp", { redstone = 4, glowstone = 1 })
craft("redstone", "lever", { stick = 1, cobblestone = 1 })
craft("redstone", "note_block", { oak_planks = 8, redstone = 1 })
craft("redstone", "jukebox", { oak_planks = 8, diamond = 1 })
craft("redstone", "lightning_rod", { copper_ingot = 3 })

---------------------------------------------------------------- TOOLS & ARMOR
local function gear(mat, item)
  craft("tool", mat .. "_sword", { [item] = 2, stick = 1 })
  craft("tool", mat .. "_pickaxe", { [item] = 3, stick = 2 })
  craft("tool", mat .. "_axe", { [item] = 3, stick = 2 })
  craft("tool", mat .. "_shovel", { [item] = 1, stick = 2 })
  craft("tool", mat .. "_hoe", { [item] = 2, stick = 2 })
  craft("armor", mat .. "_helmet", { [item] = 5 })
  craft("armor", mat .. "_chestplate", { [item] = 8 })
  craft("armor", mat .. "_leggings", { [item] = 7 })
  craft("armor", mat .. "_boots", { [item] = 4 })
end
gear("iron", "iron_ingot"); gear("golden", "gold_ingot"); gear("diamond", "diamond")
for _, g in ipairs({ { "sword", "tool" }, { "pickaxe", "tool" }, { "axe", "tool" }, { "shovel", "tool" }, { "hoe", "tool" },
  { "helmet", "armor" }, { "chestplate", "armor" }, { "leggings", "armor" }, { "boots", "armor" } }) do
  craft(g[2], "netherite_" .. g[1],
    { ["diamond_" .. g[1]] = 1, netherite_ingot = 1, netherite_upgrade_smithing_template = 1 }, { markup = 1.0 })
end

---------------------------------------------------------------- MISC UTILITY
craft("misc", "bucket", { iron_ingot = 3 }); craft("misc", "shears", { iron_ingot = 2 })
craft("misc", "flint_and_steel", { iron_ingot = 1, flint = 1 })
craft("misc", "compass", { iron_ingot = 4, redstone = 1 }); craft("misc", "clock", { gold_ingot = 4, redstone = 1 })
craft("misc", "shield", { oak_planks = 6, iron_ingot = 1 })
craft("misc", "arrow", { flint = 1, stick = 1, feather = 1 }, { out = 4 })
craft("misc", "crafting_table", { oak_planks = 4 }); craft("misc", "barrel", { oak_planks = 7 })
craft("misc", "torch", { coal = 1, stick = 1 }, { out = 4 })
craft("misc", "lantern", { iron_nugget = 8, torch = 1 })
craft("misc", "book", { paper = 3, leather = 1 }); craft("misc", "bookshelf", { oak_planks = 6, book = 3 })
craft("misc", "enchanting_table", { obsidian = 4, diamond = 2, book = 1 })
craft("misc", "anvil", { iron_block = 3, iron_ingot = 4 }); craft("misc", "cauldron", { iron_ingot = 7 })
craft("misc", "brewing_stand", { blaze_rod = 1, cobblestone = 3 })
craft("misc", "ender_chest", { obsidian = 8, ender_eye = 1 })
craft("misc", "beacon", { nether_star = 1, glass = 5, obsidian = 3 }, { markup = 1.0 })
craft("misc", "end_crystal", { glass = 7, ender_eye = 1, ghast_tear = 1 })
craft("misc", "shulker_box", { shulker_shell = 2, chest = 1 })
craft("misc", "lead", { string = 4, slime_ball = 1 }, { out = 2 })
craft("misc", "spyglass", { copper_ingot = 2, amethyst_shard = 1 })
craft("misc", "fishing_rod", { stick = 3, string = 2 })
craft("misc", "minecart", { iron_ingot = 5 }); craft("misc", "oak_boat", { oak_planks = 5 })
craft("misc", "ladder", { stick = 7 }, { out = 3 })

return list
