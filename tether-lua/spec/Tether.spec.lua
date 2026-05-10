-- Tether.spec -- TestEZ tests for the Tether client public API.
--
-- Uses Tether._newConnectedClient + _rpc override to test without a live server.
-- task.wait() after each async call lets the spawned task run before asserting.

local Tether = require(script.Parent.Parent.Tether)

-- Build a connected client whose _rpc records calls and returns canned responses.
local function mockClient(responses)
  local client = Tether._newConnectedClient({
    client_id     = "agt_test",
    client_secret = "secret",
    token_url     = "https://mock/token",
    mcp_url       = "https://mock/mcp",
    rpc_url       = "https://mock/rpc",
  })

  local calls = {}
  client._rpc = function(self, toolName, args)
    table.insert(calls, { tool = toolName, args = args })
    if responses and responses[toolName] then
      return responses[toolName]
    end
    return {}
  end

  return client, calls
end

return function()

  -- ── query ──────────────────────────────────────────────────────────────────

  describe("query", function()

    it("calls logic.query with prolog and namespace", function()
      local client, calls = mockClient({ ["data-grout@1/logic.query@1"] = { { X = "salmon" } } })
      local received
      client:query("fishing", "fish(X, rare, _)", function(r) received = r end)
      task.wait()
      expect(#calls).to.equal(1)
      expect(calls[1].tool).to.equal("data-grout@1/logic.query@1")
      expect(calls[1].args.prolog).to.equal("fish(X, rare, _)")
      expect(calls[1].args.namespace).to.equal("fishing")
    end)

    it("passes results to callback", function()
      local client = mockClient({ ["data-grout@1/logic.query@1"] = { { X = "trout" } } })
      local received
      client:query("ns", "fish(X)", function(r) received = r end)
      task.wait()
      expect(received).to.be.ok()
      expect(received[1].X).to.equal("trout")
    end)

    it("passes cached results on error", function()
      local client, calls = mockClient()
      -- Prime cache
      client._queryCache["ns|fish(X)"] = { { X = "cached" } }
      -- Make _rpc fail
      client._rpc = function() error("network error") end
      local received, err
      client:query("ns", "fish(X)", function(r, e) received = r; err = e end)
      task.wait()
      expect(received[1].X).to.equal("cached")
      expect(err).to.be.ok()
    end)

  end)

  -- ── assert ─────────────────────────────────────────────────────────────────

  describe("assert", function()

    it("calls logic.assert with facts and namespace", function()
      local client, calls = mockClient()
      client:assert("game-ns", { { type = "entity", name = "sword" } })
      task.wait()
      expect(#calls).to.equal(1)
      expect(calls[1].tool).to.equal("data-grout@1/logic.assert@1")
      expect(calls[1].args.namespace).to.equal("game-ns")
      expect(calls[1].args.facts[1].name).to.equal("sword")
    end)

    it("wraps a single fact table in an array", function()
      local client, calls = mockClient()
      client:assert("ns", { type = "entity", name = "bow" })
      task.wait()
      expect(type(calls[1].args.facts)).to.equal("table")
      expect(calls[1].args.facts[1].name).to.equal("bow")
    end)

    it("queues facts instead of calling rpc when inference_degraded", function()
      local client, calls = mockClient()
      client._status = "degraded"
      client:assert("ns", { { type = "entity", name = "queued" } })
      task.wait()
      expect(#calls).to.equal(0)
      expect(#client._assertQueue).to.equal(1)
    end)

  end)

  -- ── batteries ──────────────────────────────────────────────────────────────

  describe("batteries", function()

    it("list calls batteries.search with no required params", function()
      local client, calls = mockClient()
      client:batteries().list(function() end)
      task.wait()
      expect(#calls).to.equal(1)
      expect(calls[1].tool).to.equal("data-grout@1/batteries.search@1")
    end)

    it("install calls batteries.install_many with ids array and namespace", function()
      local client, calls = mockClient()
      client:batteries().install("quests", "my-game", function() end)
      task.wait()
      expect(#calls).to.equal(1)
      expect(calls[1].tool).to.equal("data-grout@1/batteries.install_many@1")
      expect(calls[1].args.ids[1]).to.equal("quests")
      expect(calls[1].args.namespace).to.equal("my-game")
    end)

    it("install passes result to callback", function()
      local mockResult = { installed_count = 1, results = { { id = "quests", status = "installed" } } }
      local client = mockClient({ ["data-grout@1/batteries.install_many@1"] = mockResult })
      local received
      client:batteries().install("quests", "ns", function(r) received = r end)
      task.wait()
      expect(received.installed_count).to.equal(1)
    end)

  end)

  -- ── game_rules ─────────────────────────────────────────────────────────────

  describe("game_rules", function()

    it("calls batteries.installed with namespace", function()
      local client, calls = mockClient()
      client:game_rules("my-game", function() end)
      task.wait()
      expect(#calls).to.equal(1)
      expect(calls[1].tool).to.equal("data-grout@1/batteries.installed@1")
      expect(calls[1].args.namespace).to.equal("my-game")
    end)

    it("passes installed battery list to callback", function()
      local mockResult = { namespace = "my-game", batteries = { { id = "quests", version = "1.0.0" } }, count = 1 }
      local client = mockClient({ ["data-grout@1/batteries.installed@1"] = mockResult })
      local received
      client:game_rules("my-game", function(r) received = r end)
      task.wait()
      expect(received.count).to.equal(1)
      expect(received.batteries[1].id).to.equal("quests")
    end)

  end)

  -- ── call ───────────────────────────────────────────────────────────────────

  describe("call", function()

    it("delegates to _rpc with tool name and args", function()
      local client, calls = mockClient()
      client:call("data-grout@1/math.trend@1", { values = { 1, 2, 3 } }, function() end)
      task.wait()
      expect(calls[1].tool).to.equal("data-grout@1/math.trend@1")
      expect(calls[1].args.values[1]).to.equal(1)
    end)

    it("blocks inference tools when inference_degraded", function()
      local client, calls = mockClient()
      client._status = "inference_degraded"
      local err
      client:call("data-grout@1/prism.analyze@1", {}, function(_, e) err = e end)
      task.wait()
      expect(#calls).to.equal(0)
      expect(err).to.be.ok()
    end)

    it("allows compute tools when inference_degraded", function()
      local client, calls = mockClient()
      client._status = "inference_degraded"
      client:call("data-grout@1/logic.query@1", { prolog = "x", namespace = "ns" }, function() end)
      task.wait()
      expect(#calls).to.equal(1)
    end)

  end)

  -- ── generate_rules ─────────────────────────────────────────────────────────

  describe("generate_rules", function()

    it("calls inference.invoke then logic.constrain", function()
      local client, calls = mockClient({
        ["data-grout@1/inference.invoke@1"] = { text = "rare_fish :- night, rain." },
      })
      client:generate_rules("rare fish at night", "fishing", function() end)
      task.wait()
      expect(#calls).to.equal(2)
      expect(calls[1].tool).to.equal("data-grout@1/inference.invoke@1")
      expect(calls[2].tool).to.equal("data-grout@1/logic.constrain@1")
      expect(calls[2].args.namespace).to.equal("fishing")
    end)

    it("passes generated rules text to callback", function()
      local client = mockClient({
        ["data-grout@1/inference.invoke@1"] = { text = "rule :- body." },
      })
      local received
      client:generate_rules("desc", "ns", function(r) received = r end)
      task.wait()
      expect(received).to.equal("rule :- body.")
    end)

  end)

  -- ── status ─────────────────────────────────────────────────────────────────

  describe("status", function()

    it("returns status, mcp_url, and rpc_url", function()
      local client = mockClient()
      local s = client:status()
      expect(s.status).to.equal("connected")
      expect(s.mcp_url).to.equal("https://mock/mcp")
      expect(s.rpc_url).to.equal("https://mock/rpc")
    end)

    it("reflects inference_credits when set", function()
      local client = mockClient()
      client._inferenceCredits = { remaining = 42, limit = 100 }
      local s = client:status()
      expect(s.inference_credits.remaining).to.equal(42)
    end)

  end)

end
