-- Copy to bank/config.lua and edit.
return {
  number = 1,                         -- bank number (2 digits max). Assigned by the exchange admin.
  name = "Royal Bank of Sete",
  exchange_key = "PASTE_KEY_FROM_EXCHANGE",   -- printed by `bank add` on the exchange console
  exchange_computer = nil,            -- optional fixed computer ID of the exchange (skips lookup)
  data_dir = "/bankdata",             -- accounts.db + ledger.log live here (back this folder up!)

  -- Your bank, your rules. All fees go to the bank's "house" account.
  fees = {
    deposit_pct = 0.0,                -- 0.01 = 1%
    withdraw_pct = 0.0,
    transfer_pct = 0.0,               -- applied to ATM transfers
    interbank_flat = 500,             -- cents (500 = 5.00 Cr) added to transfers leaving the bank
    max_accounts_per_owner = 3,
  },

  -- Discord webhook for notifications (optional)
  -- Set to a Discord webhook URL to enable notifications for big transfers and alerts
  discord_webhook = nil,             -- e.g. "https://discord.com/api/webhooks/..."
  discord_big_transfer_threshold = 100000,  -- cents (1000 = 10.00 Cr) minimum amount to notify
  discord_notify_pending = true,    -- notify when transfers are pending
  discord_notify_limits = true,      -- notify when bank hits interbank limits
}
