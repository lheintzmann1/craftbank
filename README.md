# CraftBank - a virtual economy for Minecraft (ComputerCraft: Tweaked)

Virtual money, **no bill items**. **1 diamond = 1,000 Cr.** Player-owned banks that talk to each other,
shops with **live prices** driven by supply and demand, and touch-screen ATMs on **1x1 monitors**
with a **single chest** in front and the cash vault hidden behind the wall.

```
                         +-----------------------+
                         |       EXCHANGE        |  clearing house + price authority
                         |  (one per server)     |  price board, events, server stats
                         +-----------+-----------+
                    encrypted rednet |  (ender modems)
              +----------------------+----------------------+
        +-----+------+                                +-----+------+
        |  BANK 01   |   <-- interbank payments -->   |  BANK 02   |   each owned by a player,
        |Royal Bank  |                                |Merchant Bk |   own fees, own customers
        +--+------+--+                                +--+------+--+
           |      |                                      |      |
        [ATM]  [SHOP]   ...                           [ATM]  [SHOP]
```

## What you get

| Folder | What it is |
|---|---|
| `common/` | shared libraries: money, SHA-256/HMAC, encrypted protocol, touch UI, inventory helpers, pricing model |
| `bank/` | bank server: accounts, PINs, sessions, deposits, transfers, pay codes, fees, admin console |
| `exchange/` | clearing house between banks (credit limits, net positions) + live market + price board + events |
| `atm/` | ATM program (1x1 touch UI, one chest in/out, vault behind the wall) |
| `shop/` | shop program: players buy and/or sell, at live market prices |
| `data/` | `base_prices.lua`: 296 items, derived from recipes so everything stays consistent |
| `tools/` | `stats_bridge.py` (real mined/crafted stats -> prices), `peripherals.lua`, price-doc generator |
| `tests/` | 35 tests, run headless with plain Lua (even the ATM and shop UIs, against a CC mock) |
| `docs/` | `SETUP.md` (build it), `DESIGN.md` (how it works), `PRICES.md` (all prices), `ROADMAP.md` |

## Highlights

* **Closed, diamond-backed money.** Money enters the system only when someone deposits diamonds at an ATM
  and leaves when diamonds are withdrawn. Shops just move money around, so there is no printing and no inflation.
* **Dynamic prices.** `price = base * exp(sensitivity * tanh(netFlow / liquidity))`. Buying pushes it up, selling and
  mining push it down, and it relaxes back to base with a 6 h half-life. Big orders slide along the curve, and
  buy-then-sell never makes a profit (tested). Random market events add flavour. Diamond is pegged.
* **Real supply data.** Optional `stats_bridge.py` feeds the server's actual mined/crafted/used/broken stats into prices.
* **Multi-bank.** Account `01-482913` = bank 01. Transfers between banks are routed by the exchange, with
  per-bank interbank fees, net positions and credit limits. The bank owners settle in diamonds (roleplay!).
* **No PIN at shops.** Customers generate a one-time **pay code** at an ATM; shops redeem it. A malicious shop owner can
  never harvest PINs.
* **Safe by design.** Encrypted + authenticated packets, replay protection, idempotent operations, PIN lockout,
  and unknown outcomes are parked as *pending* instead of guessed (no dupes, no lost money).

## Quick start

1. Push this repo to GitHub, edit `BASE` at the top of `install.lua`.
2. On the computer: `wget run https://raw.githubusercontent.com/YOU/craftbank/main/install.lua exchange` (then `bank`, `atm`, `shop` on the other computers).
3. Follow **[docs/SETUP.md](docs/SETUP.md)**: it covers the physical ATM wall, registering banks/devices and config.

Develop & test locally: `lua5.3 tests/run.lua` (needs Lua 5.2/5.3 with `bit32`).

Targets **CC: Tweaked** (Minecraft 1.16+), advanced monitors, wired + wireless/ender modems.
(OpenComputers uses a different API; the pure-logic modules `bank/core.lua`, `exchange/core.lua`, `common/pricing.lua`
would port, the I/O layers would not.)
