-- Copy to atm/config.lua and edit.   Register the ATM first on the bank console:
--     dev add atm ATM-01
return {
  device_id  = "ATM-01",
  device_key = "PASTE_KEY_FROM_BANK_CONSOLE",
  bank_no    = 1,
  bank_computer = nil,            -- optional fixed computer ID of the bank (skips lookup)
  short_name = "Royal Bank",      -- shown in the title bar (max ~15 chars on a 1x1 monitor)

  monitor = nil,                  -- peripheral name, nil = first monitor found
  text_scale = 0.5,               -- 0.5 gives 15x10 characters on a 1x1 monitor

  -- Inventories on the wired-modem network. nil = auto-detect:
  --   io_chest = the (only) chest   -> the single chest players use for deposit AND withdraw
  --   vault    = all barrels        -> the hidden cash storage behind the wall (use table, e.g. {"minecraft:shulker_box_0"})
  io_chest = nil,
  vault    = nil,

  -- what the ATM accepts for deposits: item -> value in diamonds (1 diamond = 1000 Cr)
  accept = { ["minecraft:diamond"] = 1, ["minecraft:diamond_block"] = 9 },

  allow_open_account = true,
  idle_timeout = 45,              -- seconds of inactivity before auto-logout
}
