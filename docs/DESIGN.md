# Design notes

## Money
Integer cents everywhere (`100 cents = 1 Cr`, `1 diamond = 100,000 cents`). No float math on balances.
Supply is diamond-backed: only ATM deposits create money, only withdrawals destroy it. Shops/banks move it around.

## Nodes and trust
* **Exchange** trusts only registered banks (shared 256-bit key each). It routes interbank calls, never touches accounts.
* **Bank** trusts only its registered devices (per-device key) and the exchange. A bank owner can read their own database;
  that is the RP trust model: pick a bank you trust.
* **ATM / shop** are dumb terminals. The shop can only: redeem a pay code for itself, pay out *from its own account*
  (with an optional per-transaction limit), read prices and report trades.

## Protocol (`common/protocol.lua`)
Rednet broadcasts, so confidentiality is done in software:
`packet = { d = deviceId, n = 12-byte nonce, c = ciphertext, m = HMAC }`
* ciphertext = plaintext XOR SHA-256(kenc || nonce || counter), with `kenc = HMAC(key,"enc")`
* MAC = HMAC-SHA256(`kmac`, d || n || c), `kmac = HMAC(key,"mac")`, checked in constant time
* payload carries a timestamp (30 s window) and the server remembers nonces -> no replay
* every request has an id `rid`; replies echo it
Keys never travel over the network. Per-device keys mean one stolen computer can be revoked (`dev off`).

## Safety rules (why money doesn't vanish or duplicate)
1. **Idempotent writes**: deposit / withdraw / transfer / redeem / pay_out carry a `ref`; the bank remembers the answer, so
   a retry after a lost reply returns the same result instead of acting twice.
2. **Debit first, then dispense** (withdraw). **Take items first, then pay** (shop sell), and hand them back if payment is refused.
3. **Interbank**: debit locally -> persist -> ask exchange -> destination credits (idempotent by `txid`).
   Definite failure = automatic refund. *Unknown* outcome (timeouts) = **pending**: never refunded blindly; the bank owner
   checks with the other bank and runs `pending refund <txid>` or `pending drop <txid>`.
4. ATMs that cannot learn the outcome of a deposit keep the items and write `pending.log` (ref + amount) for the owner.
5. PIN: salted, iterated SHA-256; 3 wrong tries lock the account 5 min; sessions last 2 min, are bound to one device.
6. **Pay codes**: 8 digits (`BB` + 6 random), single use, 10 min, capped amount, one live code per account; a shop that
   guesses wrong codes is throttled (8 bad tries/min).
7. Shops never learn the customer's balance, PIN or account number.

## Clearing between banks
Transfer `01 -> 02`: bank 01 debits (plus flat interbank fee), exchange forwards, bank 02 credits.
The exchange tracks `position[bank]`: negative = owes the system. Banks may not go below `limit` (default -50 diamonds).
When the owners physically pay each other diamonds, an admin runs `settle <payer> <payee> <Cr>`.

## Price model (`common/pricing.lua`)
One state variable per item: net flow `N` (units).
```
buy from shop      N += q          mined/crafted (stats)  N -= w*q   (supply)
sell to shop       N -= q          used/broken (stats)    N += w*q   (demand)
N decays with half-life 6 h
mid = base * exp(sens * tanh(N / K)) * eventMultiplier,   clamped to [0.2, 5] x base
```
* `K` (liquidity) = `6000 / base^0.6` units, e.g. cobblestone 6000, iron 650, emerald 195, netherite ingot 31.
  Cheap bulk items are deep markets, rare items are twitchy.
* `sens` by category (ore 1.15, tools 0.5...) -> price range roughly 0.3x - 3x.
* Quotes **integrate** the curve (24 steps), so a 2,000-unit order pays the sliding average, not the spot price.
* Because price depends only on `N`, buy q then sell q returns to the same price: no arbitrage loops
  (property-tested), only the shop spread is lost. Diamond (and diamond blocks) are **pegged**.
* Shops compute quotes locally from `(N, event)` fetched from the exchange, so the stepper UI is instant. A shop with a
  different price file is detected by checksum.

Example (iron ingot, base 40 Cr, K=656): after the server sells 1,000 iron the mid is ~14 Cr; 6 h later ~19 Cr;
after a day it is back at ~38 Cr.

## Where numbers come from
`data/base_prices.lua`: raw materials are hand-priced by scarcity (diamond 1000, emerald 300, gold ingot 80, iron 40,
coal 12, cobblestone 1...). Everything crafted/smelted is **derived** from its recipe (`sum(ingredients) / output * markup`),
so tools, blocks and redstone parts can never be cheaper to buy than to build from parts. See `docs/PRICES.md`.

## Known limits (v1)
* Only items **without NBT** are traded (enchanted, damaged or renamed items are ignored).
* Shop owners can wash-trade to nudge prices; the spread makes it costly, but it is possible.
* A bank owner can see their customers' data and a malicious one can steal. That is the game.
* Account numbers/names are visible only masked (`Ste***`) when sending money.
