-- Copy to shop/config.lua and edit.   Register the shop first on the bank console
-- (the shop's takings go to the owner's account, given as the 6 digits after the dash):
--     dev add shop SHOP-01 123456
return {
  device_id  = "SHOP-01",
  device_key = "PASTE_KEY_FROM_BANK_CONSOLE",
  bank_no    = 1,
  bank_computer = nil,
  name = "Steve's Ores",             -- title bar (max ~15 chars on a 1x1 monitor)

  mode = "both",                     -- "sell" (players buy from you), "buy" (players sell to you), or "both"
  spread = 0.08,                     -- total gap between your buy and sell price (0.08 = +-4% around market)

  monitor = nil, text_scale = 0.5,
  io_chest = nil,                    -- nil = auto (the only chest). Players take/put items here.
  stock = nil,                       -- nil = auto (all barrels). Your hidden storage.

  -- Which items you BUY from players, and the max you want to hold (nil = every priced item, 2048 each)
  buy_list = nil,                    -- e.g. { ["minecraft:iron_ingot"] = 4096, ["minecraft:coal"] = 2048 }
  max_stock_default = 2048,
  max_per_order = 576,               -- cap per purchase

  -- Fixed prices (cents per unit) instead of market prices. buy = player pays, sell = player receives.
  overrides = {},                    -- e.g. { ["minecraft:emerald"] = { buy = 32000, sell = 28000 } }
}
