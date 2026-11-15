-- Copy to wallet/config.lua and edit. Register the wallet first on the bank console:
--     dev add atm WALLET-01
return {
  device_id  = "WALLET-01",
  device_key = "PASTE_KEY_FROM_BANK_CONSOLE",
  bank_no    = 1,
  bank_computer = nil,            -- optional fixed computer ID of the bank (skips lookup)
}
