-- Copy to signs/config.lua and edit.
-- Configure which items to display and how they should appear.
return {
  -- Connection to exchange
  exchange_computer = nil,    -- optional fixed computer ID of the exchange (skips lookup)
  
  -- Display
  monitor = nil,              -- peripheral name, nil = first monitor found
  
  -- Display mode: "grid", "ticker", or "marquee"
  --   grid: Static grid layout showing all items at once
  --   ticker: Multi-line scrolling text
  --   marquee: Single-line scrolling (best for long monitors)
  display_mode = "ticker",
  
  -- Scrolling speed (seconds per character)
  scroll_speed = 0.2,
  
  -- Refresh interval (seconds between price updates)
  refresh_seconds = 10,
  
  -- Items to display. Can be:
  --   - Item IDs: "minecraft:diamond", "minecraft:iron_ingot"
  --   - Categories with @ prefix: "@ore", "@farm", "@food"
  --   - Item with count: "minecraft:diamond:3" (shows diamond 3 times)
  -- Leave empty to show all non-pegged items
  items = {
    -- Example: show diamonds and iron
    "minecraft:diamond",
    "minecraft:iron_ingot",
    "minecraft:gold_ingot",
    -- Example: show all ore items
    -- "@ore",
    -- Example: show food category
    -- "@food",
  },
}
