# Ideas / roadmap

**Quick wins**
- Pocket-computer wallet (balance, generate pay code, transfer) sharing `common/ui.lua`
- Auto-login via Advanced Peripherals *Player Detector* (name -> account, PIN only)
- Price history sparklines and index ("Server economy index") on the exchange board
- Discord webhook (`http.post`) for big transfers, bank pending alerts, market news
- Shop sign monitors: scrolling price boards for a whole market street

**Economy**
- Ingredient-linked prices: crafted items follow the live price of their ingredients
- Savings accounts / loans / interest paid from the bank's house account (banks compete on rates)
- Taxes & sinks: transaction tax to a "town" account that funds public projects
- Limit orders & contracts ("deliver 2,000 iron by Sunday for 90 Cr each")
- Auction house with escrow in a bank account
- Diamond-reserve ratio dashboard per bank (deposits vs. vault); bank runs become gameplay

**Infrastructure**
- Foreign cards at any ATM (routed login, with fee)
- Bank-to-bank settlement automation with a physical "armoured courier" diamond chest
- Ledger export to a web dashboard through the stats bridge
- NBT-aware valuation (durability, enchantments) with `getItemDetail`
- Generic Create/Mekanism/modded item prices (`data/mods/*.lua`)
