# Setup guide

## 0. Hardware you need
* **Exchange**: 1 computer + ender modem (+ optional big advanced monitor for the price board)
* **Each bank**: 1 computer + ender modem (or wired link to the exchange)
* **Each ATM / shop**: 1 computer, **advanced monitor 1x1**, full-block **wired modems**, networking cable, 1 **chest**, 1+ **barrels**,
  and an ender (or normal wireless) modem to reach the bank.

> Ender modems make the network range-free. With normal wireless modems all computers must be within range.

## 1. The ATM wall (one chest for deposit AND withdraw)

```
   PLAYER SIDE (public)   |  WALL / protected claim  |   SECURE SIDE (private)
                          |                          |
        [advanced monitor 1x1, at eye level]         |
                          |                          |
   player --> [ CHEST ] <-|-> [WIRED MODEM] <-> [ BARREL ] [ BARREL ]  <- the vault (cash)
                          |        |   \                                 (stack more barrels around the
                          |   [COMPUTER]  [ENDER MODEM on top of computer]   modem: it touches 6 sides)
```
* The only thing a player can touch is the **chest** and the **screen**. The vault barrels, the computer and the modems sit
  behind the wall. Protect that room with your claim/protection plugin ("even if we count on fairplay").
* A **full-block wired modem** connects every peripheral it touches. Put it directly behind the chest, put the
  barrels against its other faces, and the computer on top. **Right-click the modem** until it turns green: the chest
  and barrels then appear as `minecraft:chest_0`, `minecraft:barrel_0`...
* The monitor is on the other side of the wall: put a wired modem behind it, connect it with networking cable
  to the main modem, and right-click to activate. It shows up as `monitor_0`.
* Run `/craftbank/tools/peripherals.lua` to see the names. By default the ATM auto-detects **the only chest = I/O chest** and
  **all barrels = vault**; override in `atm/config.lua` (`io_chest`, `vault`) if you build differently.
* Stock the vault with diamonds: they are the bank's float for withdrawals. Deposits go straight into the vault.
  The bank console (`dev list`) shows each ATM's vault level so you know when to refill.

How it works: deposit = ATM moves diamonds from the chest into the vault, then credits the account. Withdraw = bank debits
first, then the ATM moves diamonds from the vault into the chest. Network or bank trouble never loses money (see DESIGN.md).

Shops use the same wall layout: chest in front (players take/put items), **barrels behind = your stock**.

## 2. Install order

### Exchange (once per server)
```
wget run https://raw.githubusercontent.com/YOU/craftbank/main/install.lua exchange
edit /craftbank/exchange/config.lua
reboot
```
On its console register every bank (use `_` for spaces in the name):
```
> bank add 1 Royal_Bank 50
Bank registered. Give the owner this exchange_key: 3f9a...
```
`50` = max net interbank debt in Cr... pass cents-free Cr, e.g. `5000` for 5,000 Cr (default 50 diamonds = 50,000 Cr).

### Bank (one per player-owned bank)
```
wget run .../install.lua bank
edit /craftbank/bank/config.lua      # number = 1, name, exchange_key (from above), fees
reboot
```
Register devices on the bank console; each prints a `device_key` for that machine:
```
> dev add atm ATM-01
> acct list                      # after the shop owner opened an account at an ATM:
> dev add shop SHOP-01 123456    # 123456 = the 6 digits of the owner's account (takings go there)
```
Other console commands: `status`, `dev list|del|off|on`, `acct info|freeze|unfreeze`, `house pay <acct> <Cr>`
(pay out bank fee income), `pending` (see DESIGN.md).

### ATM / shop
```
wget run .../install.lua atm      (or: shop)
edit /craftbank/atm/config.lua    # device_id, device_key, bank_no, short_name
reboot
```
Right after boot the ATM shows the welcome screen. Players tap **New account**, type a name on the on-screen keyboard,
choose a 4-digit PIN and get an account number like `01-482913`.

## 3. Optional: real mined/crafted data
Run on the server host: `python3 tools/stats_bridge.py /path/to/world`, then in `exchange/config.lua`:
`stats_url = "http://127.0.0.1:8765/stats"` and allow it in `config/computercraft-server.toml`
(CC blocks local addresses by default):
```toml
[[http.rules]]
	host = "127.0.0.1"
	action = "allow"
```

## 4. Player guide (put this on a sign)
1. **ATM**: New account -> write your number down. Deposit diamonds in the chest -> Deposit.
2. **Shop**: choose an item and quantity. To pay, go to an ATM -> More -> **Pay code** (max amount), then type the 8 digits at the shop.
3. **Selling** to a shop: put items in its chest -> Sell -> type *your account number*; the money arrives instantly.

## Troubleshooting
* *"Out of order: No chest on the network"*: modem not activated (right-click until green) or wrong names in config.
* *Bank unreachable*: check modems are open, bank program running, `device_key` matches `dev add`.
* *"PRICE FILE OLD!"* on a shop: update `data/base_prices.lua` on every node (checksum mismatch).
