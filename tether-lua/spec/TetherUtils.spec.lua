-- TetherUtils.spec -- TestEZ unit tests for pure Tether helpers.
--
-- Run inside Roblox Studio via the TestEZ plugin, or with Lemur for CI.
-- Place TetherUtils alongside Tether in ReplicatedStorage.

local TetherUtils = require(script.Parent.Parent.TetherUtils)

return function()

  describe("isInferenceTool", function()

    it("identifies inference tools by suite name", function()
      expect(TetherUtils.isInferenceTool("data-grout@1/prism.analyze@1")).to.equal(true)
      expect(TetherUtils.isInferenceTool("data-grout@1/prism.refract@1")).to.equal(true)
      expect(TetherUtils.isInferenceTool("data-grout@1/inference.invoke@1")).to.equal(true)
      expect(TetherUtils.isInferenceTool("data-grout@1/inference.research@1")).to.equal(true)
      expect(TetherUtils.isInferenceTool("data-grout@1/agents.orchestrate@1")).to.equal(true)
      expect(TetherUtils.isInferenceTool("data-grout@1/warden.canary@1")).to.equal(true)
      expect(TetherUtils.isInferenceTool("data-grout@1/toolsmith.forge@1")).to.equal(true)
    end)

    it("passes compute tools through as non-inference", function()
      expect(TetherUtils.isInferenceTool("data-grout@1/logic.query@1")).to.equal(false)
      expect(TetherUtils.isInferenceTool("data-grout@1/logic.assert@1")).to.equal(false)
      expect(TetherUtils.isInferenceTool("data-grout@1/math.trend@1")).to.equal(false)
      expect(TetherUtils.isInferenceTool("data-grout@1/data.filter@1")).to.equal(false)
      expect(TetherUtils.isInferenceTool("data-grout@1/batteries.install_many@1")).to.equal(false)
      expect(TetherUtils.isInferenceTool("data-grout@1/batteries.search@1")).to.equal(false)
    end)

    it("returns false for malformed tool names without version segment", function()
      expect(TetherUtils.isInferenceTool("prism.analyze")).to.equal(false)
      expect(TetherUtils.isInferenceTool("inference.invoke")).to.equal(false)
      expect(TetherUtils.isInferenceTool("")).to.equal(false)
    end)

    it("returns false for unknown suites in correctly formatted names", function()
      expect(TetherUtils.isInferenceTool("data-grout@1/unknown.tool@1")).to.equal(false)
      expect(TetherUtils.isInferenceTool("data-grout@1/prism.nonexistent@1")).to.equal(false)
    end)

  end)

  describe("unwrapRpcResult", function()

    -- Minimal JSON decoder for tests -- no Roblox service dependency
    local function decode(s)
      -- Delegate to HttpService since specs run inside Roblox
      return game:GetService("HttpService"):JSONDecode(s)
    end

    it("unwraps a standard MCP content envelope", function()
      local response = {
        result = {
          content = { { type = "text", text = '{"foo":"bar"}' } }
        }
      }
      local result = TetherUtils.unwrapRpcResult(response, decode)
      expect(result.foo).to.equal("bar")
    end)

    it("returns the result field directly when it is the value", function()
      local response = {
        result = {
          content = { { type = "text", text = '{"result":42}' } }
        }
      }
      local result = TetherUtils.unwrapRpcResult(response, decode)
      expect(result).to.equal(42)
    end)

    it("returns raw result table when there is no content envelope", function()
      local response = { result = { foo = "bar" } }
      local result = TetherUtils.unwrapRpcResult(response, decode)
      expect(result.foo).to.equal("bar")
    end)

    it("returns nil when result is absent", function()
      local result = TetherUtils.unwrapRpcResult({}, decode)
      expect(result).to.equal(nil)
    end)

    it("returns raw result when content array is empty", function()
      local response = { result = { content = {} } }
      local result = TetherUtils.unwrapRpcResult(response, decode)
      expect(result).never.to.equal(nil)
    end)

  end)

end
