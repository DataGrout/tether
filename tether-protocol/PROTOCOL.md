# Tether Protocol v0.2

JSON-RPC 2.0 over HTTP. Stateless per-request. All methods POST to the same endpoint.

## Endpoints

```
POST https://gateway.datagrout.ai/servers/{uuid}/rpc   ← JSON-RPC (Tether)
POST https://gateway.datagrout.ai/servers/{uuid}/mcp   ← MCP protocol
Authorization: Bearer {token}
Content-Type: application/json
```

Tether uses the `/rpc` endpoint. Both speak the same JSON-RPC 2.0 envelope.

## Authentication

On first connect, clients run a two-step onramp to auto-provision a free-tier identity.

**Step 1 -- initiate:**
```
POST https://gateway.datagrout.ai/onramp
Content-Type: application/json

{ "agent_name": "my-game-agent", "agent_type": "roblox-game", "intended_use": "game-logic" }
```

Response:
```json
{ "session_token": "..." }
```

**Step 2 -- complete:**
```
POST https://gateway.datagrout.ai/onramp/complete
Authorization: Bearer {session_token}
Content-Type: application/json

{}
```

Response:
```json
{
  "client_id": "agt_...",
  "client_secret": "...",
  "token_url": "https://gateway.datagrout.ai/servers/{uuid}/oauth/token",
  "mcp_url": "https://gateway.datagrout.ai/servers/{uuid}/mcp",
  "rpc_url": "https://gateway.datagrout.ai/servers/{uuid}/rpc"
}
```

Exchange credentials for a bearer token:
```
POST {token_url}
Content-Type: application/json

{ "grant_type": "client_credentials", "client_id": "...", "client_secret": "..." }
```

Token response:
```json
{ "access_token": "...", "token_type": "Bearer", "expires_in": 3600 }
```

## RPC Envelope

Request:
```json
{ "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": { "name": "...", "arguments": {} } }
```

Success response:
```json
{ "jsonrpc": "2.0", "id": 1, "result": { "content": [{ "type": "text", "text": "..." }] } }
```

Error response:
```json
{ "jsonrpc": "2.0", "id": 1, "error": { "code": -32603, "message": "..." } }
```

## Two-Class Credit Model

Tether uses two distinct credit types that reflect actual infrastructure cost.

### Compute Credits

Deterministic operations -- no LLM calls, near-zero marginal cost.

| Suite | Tools |
|---|---|
| `logic` | query, assert, constrain, remember, forget, reflect, tabulate, worlds |
| `data` | filter, sort, map, merge, aggregate, count, flatten, get, keys, pick, omit, take, unique |
| `math` | trend, outliers, rank, normalize, correlate, describe, interpolate, range, sample, sequence, window |
| `frame` | filter, group, join, pivot, pluck, select, slice, sort |
| `tasks` | list, status, wait, cancel, result |
| `ephemerals` | list, inspect |
| `runs` | list, get |

Free tier: **unlimited** compute credits (rate-limited to prevent abuse, not metered).

### Inference Credits

Operations that invoke LLM inference -- real cost per call.

| Suite | Tools | Approx. cost |
|---|---|---|
| `prism` | analyze, refract, chart, orient, horizon | 2–5 per call |
| `latent` | expand, horizon, orient | 3–8 per call |
| `inference` | invoke, search, research | 5–20 per call |
| `agents` | orchestrate, send | 10–50 per call |
| `warden` | canary, intent, ensemble, adjudicate | 2–5 per call |
| `toolsmith` | forge, temper | 5–15 per call |

Free tier: **100 inference credits/month** -- enough to use `generate_rules` during development, not enough to run LLM tools in game loops.

### Tier Allotments

| Tier | Compute | Inference | Requirement |
|---|---|---|---|
| Free | Unlimited | 100 / month | None |
| Community | Unlimited | 2,000 / month | "Powered by DataGrout" splash (3s on join) |
| Partner | Unlimited | 8,000 / month | Splash + DG link in game description |
| Featured | Unlimited | 20,000 / month | Splash + link + featured on DG showcase |
| Paid | Unlimited | Purchase-based | Billing on dashboard |

The value exchange for Community+ tiers is explicit: the splash screen unlocks LLM-backed intelligence features. Compute credits are always free because a developer calling `logic.query` in a game loop costs DG nothing meaningful.

## Credit Signals

Every response includes a `_dg` metadata field:

```json
{
  "_dg": {
    "compute_credits": { "status": "ok" },
    "inference_credits": { "remaining": 87, "limit": 100 },
    "inference_low": true,
    "inference_exhausted": false
  }
}
```

- `inference_low`: remaining inference credits < 20% of monthly allotment
- `inference_exhausted`: inference credits at 0

Clients surface `inference_low` as a developer warning (not shown to players). On `inference_exhausted`, inference-class tool calls return a typed error; compute tools continue working normally.

## Tier Error Responses

### Inference credits exhausted (free tier)

```json
{
  "error": {
    "code": -32001,
    "message": "inference_exhausted",
    "data": {
      "remaining": 0,
      "reset_at": "2026-06-01T00:00:00Z",
      "upgrade_url": "https://app.datagrout.ai/tether"
    }
  }
}
```

### Tier insufficient for tool

```json
{
  "error": {
    "code": -32002,
    "message": "tier_required",
    "data": {
      "required_tier": "community",
      "tool": "inference.invoke",
      "upgrade_url": "https://app.datagrout.ai/tether"
    }
  }
}
```

Client SDK behaviour: print upgrade URL to Studio output / developer console. Call the error callback with a descriptive string. Never surface credit errors to players. Compute tools continue working in all cases.

## Degraded Mode

Triggered only when inference credits reach 0. Compute tools are never degraded.

1. `logic.query` -- continues normally
2. `logic.assert` -- continues normally
3. `invoke`, `orchestrate` -- return `inference_exhausted` error
4. `dg:call` on inference-class tools -- return `inference_exhausted` error
5. `dg:status()` returns `"inference_degraded"` (not `"degraded"` -- compute still works)

Inference tools restore automatically at monthly reset or when credits are purchased.

## Tool Catalog

Full catalog accessible via `dg:call`. See `discovery.summary` for the current list (118+ tools).

Compute tools are safe to call in tight game loops -- they are deterministic, fast, and cost nothing beyond the free rate limit. Inference tools should be called intentionally (on player join, on quest generation, on rule setup) rather than per-frame.
