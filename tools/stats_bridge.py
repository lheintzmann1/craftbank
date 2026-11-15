#!/usr/bin/env python3
"""
Stats bridge: exposes the Minecraft server's REAL mined/crafted/used/broken totals to the exchange.

Vanilla servers keep per-player statistics in <world>/stats/<uuid>.json. This script sums them over all
players and serves the cumulative totals as JSON. The exchange polls it, remembers the previous totals and
converts the *difference* into supply/demand pressure on prices (mined/crafted -> supply, used/broken -> demand).

    python3 stats_bridge.py /path/to/world            # listens on 127.0.0.1:8765
    python3 stats_bridge.py /path/to/world --port 9000 --host 0.0.0.0

In-game: set  stats_url = "http://127.0.0.1:8765/stats"  in exchange/config.lua and allow that address in
config/computercraft-server.toml ( [[http.rules]]: host = "127.0.0.1", action = "allow" ) - CC blocks local
addresses by default.
Note: the server writes stats files periodically (autosave / player logout), so data lags a few minutes.
"""
import argparse, glob, json, os, time
from http.server import BaseHTTPRequestHandler, HTTPServer

# Mining a block does not give the block's own item for ores: map block -> (item, average drops per block).
MINED_ALIAS = {
    "coal_ore": ("coal", 1), "deepslate_coal_ore": ("coal", 1),
    "iron_ore": ("raw_iron", 1), "deepslate_iron_ore": ("raw_iron", 1),
    "copper_ore": ("raw_copper", 3), "deepslate_copper_ore": ("raw_copper", 3),
    "gold_ore": ("raw_gold", 1), "deepslate_gold_ore": ("raw_gold", 1), "nether_gold_ore": ("gold_nugget", 4),
    "redstone_ore": ("redstone", 4), "deepslate_redstone_ore": ("redstone", 4),
    "lapis_ore": ("lapis_lazuli", 6), "deepslate_lapis_ore": ("lapis_lazuli", 6),
    "diamond_ore": ("diamond", 1), "deepslate_diamond_ore": ("diamond", 1),
    "emerald_ore": ("emerald", 1), "deepslate_emerald_ore": ("emerald", 1),
    "nether_quartz_ore": ("quartz", 1), "ancient_debris": ("netherite_scrap", 1),
    "stone": ("cobblestone", 1), "grass_block": ("dirt", 1),
    "carrots": ("carrot", 1), "potatoes": ("potato", 2), "beetroots": ("beetroot", 1),
    "wheat": ("wheat", 1), "sugar_cane": ("sugar_cane", 1), "melon": ("melon_slice", 5),
}
CATS = {"minecraft:mined": "mined", "minecraft:crafted": "crafted",
        "minecraft:used": "used", "minecraft:broken": "broken"}


def collect(world):
    out = {"mined": {}, "crafted": {}, "used": {}, "broken": {}}
    files = glob.glob(os.path.join(world, "stats", "*.json"))
    for path in files:
        try:
            with open(path) as f:
                stats = json.load(f).get("stats", {})
        except (OSError, ValueError):
            continue
        for key, cat in CATS.items():
            for name, n in stats.get(key, {}).items():
                short = name.split(":", 1)[-1]
                if cat == "mined" and short in MINED_ALIAS:
                    short, mult = MINED_ALIAS[short]
                    n = n * mult
                item = "minecraft:" + short
                out[cat][item] = out[cat].get(item, 0) + n
    out["players"] = len(files)
    out["ts"] = int(time.time())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("world")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    cache = {"t": 0, "data": None}

    class H(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/stats":
                self.send_error(404); return
            if time.time() - cache["t"] > 20:
                cache["data"], cache["t"] = collect(args.world), time.time()
            body = json.dumps(cache["data"]).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers(); self.wfile.write(body)
        def log_message(self, *a): pass

    print(f"serving {args.world}/stats on http://{args.host}:{args.port}/stats")
    HTTPServer((args.host, args.port), H).serve_forever()


if __name__ == "__main__":
    main()
