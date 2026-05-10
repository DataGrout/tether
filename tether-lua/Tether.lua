--[[
  Tether v0.2 -- DataGrout connector for Roblox (Luau)

  Drop this ModuleScript into ReplicatedStorage and require it from a Script.
  First connect() auto-bootstraps a free-tier DG account -- no API key needed.

  Usage:
    local Tether = require(game.ReplicatedStorage.Tether)
    local dg = Tether.connect()
    dg:query("my-game", "fish(X, rare, _)", function(results) print(results) end)
--]]

local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local TetherUtils = require(script.Parent:FindFirstChild("TetherUtils"))

-- ── Config ────────────────────────────────────────────────────────────────────

local DG_BASE_URL   = "https://gateway.datagrout.ai"
local ONRAMP_URL    = DG_BASE_URL .. "/onramp"
local IDENTITY_KEY  = "TetherIdentity_v2"
local TOKEN_REFRESH = 3300  -- seconds before expiry to refresh (55 min of 60)
local POLL_INTERVAL = 2     -- seconds between watch polls
local MAX_RETRIES   = 3

-- ── State ─────────────────────────────────────────────────────────────────────

local Client = {}
Client.__index = Client

local function newClient()
  return setmetatable({
    _mcpUrl           = nil,
    _rpcUrl           = nil,
    _token            = nil,
    _tokenExpiry      = 0,
    _clientId         = nil,
    _clientSecret     = nil,
    _tokenUrl         = nil,
    _status           = "disconnected",  -- disconnected|connecting|connected|inference_degraded
    _inferenceCredits = nil,             -- { remaining, limit }
    _queryCache       = {},
    _assertQueue      = {},
    _watches          = {},
    _rpcId            = 0,
  }, Client)
end

-- ── Identity persistence ──────────────────────────────────────────────────────
--
-- Priority order for loading credentials:
--   1. TetherConfig sibling module  (Rojo / Wally / CLI users)
--   2. plugin:GetSetting()          (Studio plugin users)
--   3. DataStoreService             (previously-bootstrapped published games)
--   4. nil -> fall through to full onramp bootstrap

local function loadFromConfigModule()
  -- Rojo projects generate a TetherConfig.lua via `tether-cli init`.
  -- It lives alongside Tether.lua in ReplicatedStorage and is gitignored.
  local ok, cfg = pcall(function()
    return require(script.Parent:FindFirstChild("TetherConfig"))
  end)
  if ok and cfg and cfg.client_id then return cfg end
  return nil
end

local function loadFromPlugin()
  -- Studio plugin stores credentials via plugin:SetSetting().
  -- Only available when running inside Roblox Studio.
  local ok, result = pcall(function()
    -- plugin is a global only present in plugin scripts; guard with pcall
    if not plugin then return nil end  -- luacheck: ignore
    local raw = plugin:GetSetting(IDENTITY_KEY)  -- luacheck: ignore
    if raw then return HttpService:JSONDecode(raw) end
    return nil
  end)
  if ok and result and result.client_id then return result end
  return nil
end

local function saveToPlugin(data)
  pcall(function()
    if not plugin then return end  -- luacheck: ignore
    plugin:SetSetting(IDENTITY_KEY, HttpService:JSONEncode(data))  -- luacheck: ignore
  end)
end

local function saveIdentity(data)
  -- Try plugin storage first (Studio), then DataStore (published game)
  saveToPlugin(data)
  local ok, err = pcall(function()
    local store = DataStoreService:GetDataStore("TetherSDK")
    store:SetAsync(IDENTITY_KEY, HttpService:JSONEncode(data))
  end)
  if not ok then
    warn("[Tether] DataStore unavailable (expected in Studio): " .. tostring(err))
  end
end

local function loadIdentity()
  -- 1. Rojo/CLI config module
  local cfg = loadFromConfigModule()
  if cfg then return cfg end

  -- 2. Studio plugin settings
  cfg = loadFromPlugin()
  if cfg then return cfg end

  -- 3. DataStore (published game)
  local ok, result = pcall(function()
    local store = DataStoreService:GetDataStore("TetherSDK")
    local raw = store:GetAsync(IDENTITY_KEY)
    if raw then return HttpService:JSONDecode(raw) end
    return nil
  end)
  if ok and result then return result end

  return nil
end

-- ── HTTP helpers ──────────────────────────────────────────────────────────────

local function post(url, body, token)
  local headers = { ["Content-Type"] = "application/json" }
  if token then headers["Authorization"] = "Bearer " .. token end
  local response = HttpService:RequestAsync({
    Url     = url,
    Method  = "POST",
    Headers = headers,
    Body    = HttpService:JSONEncode(body),
  })
  if not response.Success then
    error("[Tether] HTTP " .. response.StatusCode .. " from " .. url)
  end
  return HttpService:JSONDecode(response.Body)
end

-- ── OAuth token exchange ──────────────────────────────────────────────────────

function Client:_refreshToken()
  local data = post(self._tokenUrl, {
    grant_type    = "client_credentials",
    client_id     = self._clientId,
    client_secret = self._clientSecret,
  })
  self._token       = data.access_token
  self._tokenExpiry = os.time() + (data.expires_in or 3600) - 60
end

function Client:_ensureToken()
  if os.time() >= self._tokenExpiry then
    self:_refreshToken()
  end
end

-- ── JSON-RPC call ─────────────────────────────────────────────────────────────

function Client:_rpc(toolName, args, retries)
  retries = retries or 0
  self:_ensureToken()

  self._rpcId = self._rpcId + 1
  local envelope = {
    jsonrpc = "2.0",
    id      = self._rpcId,
    method  = "tools/call",
    params  = { name = toolName, arguments = args or {} },
  }

  local ok, response = pcall(post, self._rpcUrl, envelope, self._token)
  if not ok then
    if retries < MAX_RETRIES then
      task.wait(2 ^ retries)
      return self:_rpc(toolName, args, retries + 1)
    end
    error(response)
  end

  -- Track inference credits separately from compute (compute is always free)
  local meta = response._dg
  if meta then
    if meta.inference_credits then
      self._inferenceCredits = meta.inference_credits
    end
    if meta.inference_exhausted then
      if self._status == "connected" then
        self._status = "inference_degraded"
        warn("[Tether] Inference credits exhausted. Compute tools still work. " ..
             "Upgrade at: https://app.datagrout.ai/tether")
      end
    elseif self._status == "inference_degraded" then
      -- Credits restored (purchase or monthly reset)
      self._status = "connected"
      self:_flushAssertQueue()
    end
    if meta.inference_low then
      local rem = self._inferenceCredits and self._inferenceCredits.remaining or "?"
      warn("[Tether] Inference credits low: " .. tostring(rem) .. " remaining.")
    end
  end

  if response.error then
    local err = response.error
    -- Surface tier errors with upgrade guidance rather than a raw code
    if err.message == "tier_required" and err.data then
      local url = err.data.upgrade_url or "https://app.datagrout.ai/tether"
      warn("[Tether] " .. (err.data.method or toolName) .. " requires " ..
           (err.data.required_tier or "a higher") .. " tier. Upgrade at: " .. url)
      error("tier_required:" .. (err.data.required_tier or "community"))
    end
    error("[Tether] RPC error " .. err.code .. ": " .. err.message)
  end

  return TetherUtils.unwrapRpcResult(response, function(s) return HttpService:JSONDecode(s) end)
end

-- ── Degraded mode helpers ─────────────────────────────────────────────────────

function Client:_flushAssertQueue()
  -- assert is a compute tool -- always safe to flush regardless of inference status
  local queue = self._assertQueue
  self._assertQueue = {}
  for _, item in ipairs(queue) do
    pcall(function()
      self:_rpc("data-grout@1/logic.assert@1", { facts = item.facts, namespace = item.namespace })
    end)
  end
end

function Client:_checkInferenceDegraded(toolName, callback)
  if self._status == "inference_degraded" and TetherUtils.isInferenceTool(toolName) then
    local msg = "inference_exhausted: upgrade at https://app.datagrout.ai/tether"
    if callback then callback(nil, msg) end
    return true
  end
  return false
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Query Prolog facts from a namespace.
-- callback(results, err) -- results is a list of binding maps.
function Client:query(namespace, prolog, callback)
  local cacheKey = namespace .. "|" .. prolog

  if self._status == "degraded" then
    local cached = self._queryCache[cacheKey]
    if callback then callback(cached or {}, "degraded") end
    return
  end

  task.spawn(function()
    local ok, result = pcall(function()
      return self:_rpc("data-grout@1/logic.query@1", { prolog = prolog, namespace = namespace })
    end)
    if ok then
      self._queryCache[cacheKey] = result
      if callback then callback(result, nil) end
    else
      if callback then callback(self._queryCache[cacheKey] or {}, result) end
    end
  end)
end

-- Assert facts into a namespace.
-- facts: array of fact objects (see tether-protocol/PROTOCOL.md).
function Client:assert(namespace, facts)
  if type(facts) ~= "table" then facts = { facts } end

  if self._status == "degraded" then
    table.insert(self._assertQueue, { namespace = namespace, facts = facts })
    return
  end

  task.spawn(function()
    pcall(function()
      self:_rpc("data-grout@1/logic.assert@1", { facts = facts, namespace = namespace })
    end)
  end)
end

-- Poll for fact changes matching a Prolog pattern.
-- opts: { interval = seconds }
-- Returns a handle with :stop() method.
function Client:watch(namespace, pattern, callback, opts)
  opts = opts or {}
  local interval = opts.interval or POLL_INTERVAL
  local cacheKey = namespace .. "|" .. pattern
  local running  = true

  task.spawn(function()
    while running do
      self:query(namespace, pattern, function(results, err)
        if not err then
          local prev = self._queryCache[cacheKey .. "_prev"]
          local cur  = HttpService:JSONEncode(results)
          if prev ~= cur then
            self._queryCache[cacheKey .. "_prev"] = cur
            if callback then callback(results) end
          end
        end
      end)
      task.wait(interval)
    end
  end)

  return { stop = function() running = false end }
end

-- Run LLM inference (inference credit -- Community+).
function Client:invoke(prompt, opts, callback)
  if self:_checkInferenceDegraded("data-grout@1/inference.invoke@1", callback) then return end
  opts = opts or {}
  task.spawn(function()
    local ok, result = pcall(function()
      return self:_rpc("data-grout@1/inference.invoke@1", {
        prompt = prompt,
        system = opts.system,
      })
    end)
    if callback then callback(ok and result or nil, ok and nil or result) end
  end)
end

-- Run a multi-agent workflow (inference credit -- Community+).
function Client:orchestrate(agentId, input, callback)
  if self:_checkInferenceDegraded("data-grout@1/agents.orchestrate@1", callback) then return end
  task.spawn(function()
    local ok, result = pcall(function()
      return self:_rpc("data-grout@1/agents.orchestrate@1", {
        agent_id = agentId,
        input    = input,
      })
    end)
    if callback then callback(ok and result or nil, ok and nil or result) end
  end)
end

-- LLM generates Prolog rules for a game mechanic (inference credit -- 100 free/mo).
-- Generated rules are loaded into namespace immediately via logic.constrain.
function Client:generate_rules(description, namespace, callback)
  if self:_checkInferenceDegraded("data-grout@1/inference.invoke@1", callback) then return end
  task.spawn(function()
    local ok, result = pcall(function()
      local inferResult = self:_rpc("data-grout@1/inference.invoke@1", {
        system = "You are a Prolog expert. Generate valid SWI-Prolog rules for the " ..
                 "described game mechanic. Output ONLY the Prolog rules, no explanation.",
        prompt = "Game mechanic: " .. description .. "\n\nGenerate Prolog rules:",
      })
      local rulesText = type(inferResult) == "table" and inferResult.text or tostring(inferResult)
      -- logic.constrain handles multi-clause Prolog rules correctly
      self:_rpc("data-grout@1/logic.constrain@1", {
        namespace = namespace,
        prolog    = rulesText,
      })
      return rulesText
    end)
    if callback then callback(ok and result or nil, ok and nil or result) end
  end)
end

-- Call any tool in the DG catalog directly.
-- Compute tools (logic/data/math/frame) are always free and safe in game loops.
-- Inference tools (prism/latent/inference/agents) consume inference credits --
-- call them intentionally (on join, on setup), not per-frame.
function Client:call(toolName, args, callback)
  if self:_checkInferenceDegraded(toolName, callback) then return end
  task.spawn(function()
    local ok, result = pcall(function()
      return self:_rpc(toolName, args)
    end)
    if callback then callback(ok and result or nil, ok and nil or result) end
  end)
end

-- Return connection status and credit info.
function Client:status()
  return {
    status            = self._status,
    inference_credits = self._inferenceCredits,
    mcp_url           = self._mcpUrl,
    rpc_url           = self._rpcUrl,
  }
end

-- ── Battery module manager ────────────────────────────────────────────────────

-- Browse and install prebuilt Prolog rulesets from the LC Batteries catalog.
-- Installed batteries are loaded into the target namespace and become
-- immediately queryable -- including by orchestrate if the namespace is passed.
--
--   dg:batteries().list(function(result, err) ... end)
--   dg:batteries().install("quests", "my-game", function(result, err) ... end)
function Client:batteries()
  local client = self

  return {
    -- Search the battery catalog.
    -- callback(result, err) -- result: { modules: [{id, title, description, ...}] }
    list = function(callback)
      task.spawn(function()
        local ok, result = pcall(function()
          return client:_rpc("data-grout@1/batteries.search@1", {})
        end)
        if callback then callback(ok and result or nil, ok and nil or result) end
      end)
    end,

    -- Install a battery's rules into namespace.
    -- callback(result, err) -- result: { installed: [{id, version, status}] }
    install = function(batteryId, namespace, callback)
      task.spawn(function()
        local ok, result = pcall(function()
          return client:_rpc("data-grout@1/batteries.install_many@1", {
            ids       = { batteryId },
            namespace = namespace,
          })
        end)
        if callback then callback(ok and result or nil, ok and nil or result) end
      end)
    end,
  }
end

-- List installed batteries in namespace.
-- callback(result, err) -- result: { namespace, batteries: [{id, version}], count }
function Client:game_rules(namespace, callback)
  task.spawn(function()
    local ok, result = pcall(function()
      return self:_rpc("data-grout@1/batteries.installed@1", { namespace = namespace })
    end)
    if callback then callback(ok and result or nil, ok and nil or result) end
  end)
end

-- ── Bootstrap / Connect ───────────────────────────────────────────────────────

local function bootstrap(agentName)
  -- Try to load a persisted identity first
  local identity = loadIdentity()

  if identity then
    print("[Tether] Resuming identity: " .. tostring(identity.client_id))
    return identity
  end

  -- First run: two-step onramp to auto-provision free-tier account
  print("[Tether] No identity found -- registering with DataGrout (free tier)…")

  -- Step 1: initiate registration, receive session token
  local step1 = post(ONRAMP_URL, {
    agent_name   = agentName or (game.Name .. "-agent"),
    agent_type   = "roblox-game",
    intended_use = "game-logic",
  })

  -- Step 2: complete registration with session token, receive credentials
  local step2 = post(ONRAMP_URL .. "/complete", {}, step1.session_token)

  local identity2 = {
    client_id     = step2.client_id,
    client_secret = step2.client_secret,
    token_url     = step2.token_url,
    mcp_url       = step2.mcp_url,
    rpc_url       = step2.rpc_url,
  }

  saveIdentity(identity2)
  print("[Tether] Registered! Free tier: 5,000 credits/month.")
  print("[Tether] Upgrade at: https://app.datagrout.ai")
  return identity2
end

-- ── Public: Tether.connect(opts) ─────────────────────────────────────────────

local Tether = {}

-- Connect to DataGrout.  opts:
--   agent_name (string) -- name for this game agent (default: game name)
--   mcp_url    (string) -- override MCP server URL (for existing accounts)
--   rpc_url    (string) -- override JSON-RPC URL (for existing accounts)
function Tether.connect(opts)
  opts = opts or {}
  local client = newClient()
  client._status = "connecting"

  task.spawn(function()
    local ok, err = pcall(function()
      local identity = bootstrap(opts.agent_name)
      client._clientId     = identity.client_id
      client._clientSecret = identity.client_secret
      client._tokenUrl     = identity.token_url
      client._mcpUrl       = opts.mcp_url or identity.mcp_url
      client._rpcUrl       = opts.rpc_url or identity.rpc_url
      client:_refreshToken()
      client._status = "connected"
      print("[Tether] Connected. RPC: " .. client._rpcUrl)
    end)
    if not ok then
      client._status = "disconnected"
      warn("[Tether] Connection failed: " .. tostring(err))
    end
  end)

  return client
end

-- Creates a pre-connected client with a mocked identity -- for tests only.
-- Bypasses bootstrap and token refresh so tests need no live HTTP calls.
-- Override client._rpc after calling this to inject mock responses.
function Tether._newConnectedClient(identity)
  local client = newClient()
  client._clientId     = identity.client_id
  client._clientSecret = identity.client_secret
  client._tokenUrl     = identity.token_url
  client._mcpUrl       = identity.mcp_url
  client._rpcUrl       = identity.rpc_url
  client._token        = "test_token"
  client._tokenExpiry  = math.huge  -- never expires in tests
  client._status       = "connected"
  return client
end

return Tether
