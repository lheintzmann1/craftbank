-- Copy to exchange/config.lua and edit.
return {
  data_dir = "/exchdata",
  halflife_hours = 6,          -- how fast supply/demand pressure fades (price drifts back to base)
  events = true,               -- random market events ("Drought hits crops", ...)
  default_limit = 5000000,     -- cents: max net interbank debt per bank (5,000,000 = 50 diamonds)

  -- Optional: real mined/crafted statistics from the Minecraft server (see tools/stats_bridge.py).
  -- Needs the host allowed in computercraft-server.toml ([[http.rules]]).
  stats_url = nil,             -- e.g. "http://127.0.0.1:8765/stats"
  stats_poll = 120,            -- seconds
  stat_weights = { mined = 0.5, crafted = 0.3, used = 0.25, broken = 0.5 },

  -- Price history for sparklines on the board
  history_length = 24,          -- number of data points to keep for sparklines
  history_interval_minutes = 5, -- how often to record price history

  -- Discord webhook for market news
  discord_webhook = nil,       -- e.g. "https://discord.com/api/webhooks/..."

  monitor = nil,               -- peripheral name of the price-board monitor (nil = auto-detect, none = no board)
}
