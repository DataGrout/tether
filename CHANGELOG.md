# Changelog

All notable changes to Tether are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.2.0] - 2026-05-09

### Added
- `rpc_url` in identity -- JSON-RPC calls now use a dedicated `/rpc` endpoint separate from the MCP `/mcp` endpoint.
- `dg:batteries()` -- new name for the module manager (see below). Includes `list` and `install` methods.
- `dg:status()` now returns `rpc_url` alongside `mcp_url`.
- `rpc_url` override option in `Tether.connect(opts)`.

### Changed
- **Bootstrap flow**: Registration now uses a two-step onramp (`POST /onramp` -> `POST /onramp/complete`) instead of a single `/onboard` call. First connect after upgrading re-registers automatically (free, instant).
- **`dg:modules()` renamed to `dg:batteries()`**: Matches the LC Batteries catalog naming. The `install` method now delegates rule parsing to the server-side `batteries.install_many` tool rather than fetching and pushing raw Prolog from the client.
- **`dg:query()` field fix**: Raw Prolog queries now correctly send `{ prolog = "..." }` instead of the wrong `{ query = "..." }`.
- **`dg:generate_rules()` uses `logic.constrain`**: Generated rules are loaded via the constrain pipeline, which correctly handles multi-clause Prolog predicates. `logic.assert` with `raw_prolog` was silently dropping rules.
- **`dg:game_rules()` uses `batteries.installed`**: Lists installed batteries via the tracking API instead of querying `tether_module`/`tether_export` facts, which are not present after a `batteries.install_many` install.
- Identity key bumped to `TetherIdentity_v2` -- avoids stale credential structs that are missing `rpc_url`.

### Fixed
- `tether-cli`: two-step onramp, `rpc_url` written to generated `TetherConfig.lua`.

## [0.1.0] - Initial release

Luau SDK for Roblox with compute/inference credit model, OAuth token management, degraded mode, and `dg:call` escape hatch.
