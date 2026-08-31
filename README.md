# Tether

[![CI](https://github.com/datagrout/tether/actions/workflows/ci.yml/badge.svg)](https://github.com/datagrout/tether/actions/workflows/ci.yml)

Lightweight DataGrout connectors for game engines.

Connect your game to DG's full intelligence layer in minutes. Free tier auto-provisions on first connect -- no API key, no dashboard, no configuration.

```lua
local Tether = require(game.ServerStorage.Tether)
local dg = Tether.connect()

-- Query game logic facts (free)
dg:query("fishing-game", "fish(X, rare, _)", function(results)
  spawnRareFish(results)
end)

-- Let the LLM write your game rules (Community+)
dg:generate_rules("rare fish only appear at night during rain", "fishing-game", function(rules)
  print("Rules generated: " .. rules)
end)

-- Call any DG tool directly -- 118+ available
dg:call("data-grout@1/math.trend@1", { values = salesData }, function(result)
  updateLeaderboard(result)
end)
```

## Getting Started

Three paths depending on your workflow:

### Studio Plugin (beginners)
Install **Tether by DataGrout** from the Creator Marketplace. Click Connect in the toolbar -- credentials bootstrap automatically and `Tether.lua` is inserted into your game.

### Rojo + Wally (serious developers)

```toml
# wally.toml
[dependencies]
Tether = "datagrout/tether@0.2.0"
```

```bash
wally install
tether init          # bootstrap credentials → writes TetherConfig.lua
rojo serve           # TetherConfig syncs alongside Tether into Studio
```

`tether-cli` is a small Rust binary: `cargo install tether-cli` or download from the releases page.

`TetherConfig.lua` is gitignored automatically. Teammates run `tether init` once on their machine.

### Manual (any setup)
Drop `tether-lua/Tether.lua` into **ServerStorage**. First `connect()` call bootstraps a free-tier account automatically.

> **Security:** keep Tether and `TetherConfig.lua` in ServerStorage (or ServerScriptService), never ReplicatedStorage — everything in ReplicatedStorage replicates to every player's client, credentials included. Tether is server-only anyway: Roblox only allows HTTP from the server.

---

## Protocol

See `tether-protocol/PROTOCOL.md` for the JSON-RPC message format, auth flow, credit signals, tier gating, and degraded mode spec.

## Credit Model

Tether uses two credit types that reflect actual infrastructure cost.

**Compute credits** -- deterministic tools (`logic.*`, `data.*`, `math.*`, `frame.*`). Near-zero marginal cost. **Free tier: unlimited** (rate-limited, not metered). Safe to call in game loops.

**Inference credits** -- tools that invoke LLM inference (`prism.*`, `latent.*`, `inference.*`, `agents.*`). Real cost per call. Gated by tier.

| Tier | Inference Credits | Requirement |
|---|---|---|
| Free | 100 / month | None |
| Community | 2,000 / month | "Powered by DataGrout" splash (3s on join) |
| Partner | 8,000 / month | Splash + DG link in game description |
| Featured | 20,000 / month | Splash + link + featured on DG showcase |
| Paid | Purchase-based | Billing on dashboard |

The free tier's 100 inference credits are sized for development use of `generate_rules` -- enough to build, not enough to run LLM tools in production game loops. The Community tier unlocks that. The value exchange is explicit: the splash screen is the price of LLM-backed game intelligence.

## API

### Named convenience methods

```lua
dg:query(namespace, prolog, callback)        -- Query LC facts              [compute -- free]
dg:assert(namespace, facts)                  -- Assert facts into LC        [compute -- free]
dg:watch(namespace, pattern, callback, opts) -- Poll for fact changes       [compute -- free]
dg:invoke(prompt, opts, callback)            -- LLM inference               [inference -- Community+]
dg:orchestrate(agent_id, input, callback)    -- Multi-agent workflow        [inference -- Community+]
dg:generate_rules(description, ns, callback) -- LLM writes your Prolog      [inference -- 100 free/mo]
dg:batteries().list(callback)               -- Browse battery catalog       [compute -- free]
dg:batteries().install(id, ns, callback)    -- Install a battery            [compute -- free]
dg:game_rules(namespace, callback)          -- List installed batteries     [compute -- free]
```

### General escape hatch -- call any DG tool

```lua
dg:call(tool_name, args, callback)
```

Exposes all 118+ tools in the DG catalog. Compute tools are safe in game loops. Inference tools consume inference credits and should be called intentionally (on join, on quest start, on rule setup) -- not per-frame.

```lua
-- Compute tools -- safe in game loops, always free
dg:call("data-grout@1/math.trend@1",    { values = {10,12,15,11,18} }, cb)
dg:call("data-grout@1/math.rank@1",     { values = playerScores }, cb)
dg:call("data-grout@1/data.filter@1",   { data = items, where = "level > 5" }, cb)
dg:call("data-grout@1/data.sort@1",     { data = leaderboard, by = "score" }, cb)
dg:call("data-grout@1/frame.group@1",   { data = events, by = "player_id" }, cb)

-- Inference tools -- call intentionally, consume inference credits
dg:call("data-grout@1/prism.analyze@1", { data = gameLog, goal = "find patterns" }, cb)
dg:call("data-grout@1/latent.expand@1", { seed = "dungeon", domain_hint = "fantasy rpg" }, cb)
```

### Meta

```lua
dg:status()
-- {
--   status = "connecting"|"connected"|"inference_degraded"|"disconnected",
--   inference_credits = { remaining = 87, limit = 100 },
--   mcp_url = "...",
--   rpc_url = "..."
-- }
```

## Credit Exhaustion

When inference credits reach 0, only inference-class tools are affected. Compute tools (`logic.*`, `data.*`, `math.*`, `frame.*`) continue working normally -- degraded mode never touches game logic. The SDK surfaces `inference_exhausted` errors to the developer (Studio output / server console), never to players.

## License

MIT
