-- lune_tests.luau — TetherUtils tests runnable with lune (no Roblox required).
--
-- The full Tether.spec (client API) runs inside Roblox Studio via TestEZ
-- because it depends on task.spawn and the Roblox scheduler.
--
-- Run: lune run tether-lua/lune_tests.luau

local process = require("@lune/process")
local serde   = require("@lune/serde")
local TetherUtils = require("./TetherUtils")

local passed = 0
local failed = 0

local function test(name: string, fn: () -> ())
  local ok, err = pcall(fn)
  if ok then
    print("  \x1b[32m✓\x1b[0m " .. name)
    passed += 1
  else
    print("  \x1b[31m✗\x1b[0m " .. name)
    print("    " .. tostring(err))
    failed += 1
  end
end

local function eq(a, b)
  assert(a == b, ("expected %s, got %s"):format(tostring(b), tostring(a)))
end

local function decode(s: string)
  return serde.decode("json", s)
end

-- ── isInferenceTool ───────────────────────────────────────────────────────────

print("isInferenceTool")

test("identifies prism.analyze as inference", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/prism.analyze@1"), true)
end)
test("identifies prism.refract as inference", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/prism.refract@1"), true)
end)
test("identifies inference.invoke as inference", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/inference.invoke@1"), true)
end)
test("identifies inference.research as inference", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/inference.research@1"), true)
end)
test("identifies agents.orchestrate as inference", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/agents.orchestrate@1"), true)
end)
test("identifies warden.canary as inference", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/warden.canary@1"), true)
end)
test("identifies toolsmith.forge as inference", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/toolsmith.forge@1"), true)
end)

test("passes logic.query as compute", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/logic.query@1"), false)
end)
test("passes logic.assert as compute", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/logic.assert@1"), false)
end)
test("passes math.trend as compute", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/math.trend@1"), false)
end)
test("passes data.filter as compute", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/data.filter@1"), false)
end)
test("passes batteries.install_many as compute", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/batteries.install_many@1"), false)
end)

test("returns false for name without version segment", function()
  eq(TetherUtils.isInferenceTool("prism.analyze"), false)
end)
test("returns false for empty string", function()
  eq(TetherUtils.isInferenceTool(""), false)
end)
test("returns false for unknown suite in valid format", function()
  eq(TetherUtils.isInferenceTool("data-grout@1/unknown.tool@1"), false)
end)

-- ── unwrapRpcResult ───────────────────────────────────────────────────────────

print("\nunwrapRpcResult")

test("unwraps a standard MCP content envelope", function()
  local response = {
    result = { content = { { type = "text", text = '{"foo":"bar"}' } } }
  }
  local result = TetherUtils.unwrapRpcResult(response, decode)
  eq(result.foo, "bar")
end)

test("returns the result field directly when it is the value", function()
  local response = {
    result = { content = { { type = "text", text = '{"result":42}' } } }
  }
  local result = TetherUtils.unwrapRpcResult(response, decode)
  eq(result, 42)
end)

test("returns nil result field when result is false-y", function()
  local response = {
    result = { content = { { type = "text", text = '{"result":null}' } } }
  }
  -- result field is nil/null, so decoded.result ~= nil is false → returns decoded
  local result = TetherUtils.unwrapRpcResult(response, decode)
  -- decoded = { result = nil }, so decoded.result is nil → returns decoded (the table)
  assert(type(result) == "table", "should return decoded table when result key is null")
end)

test("returns raw result table when no content envelope", function()
  local response = { result = { foo = "bar" } }
  local result = TetherUtils.unwrapRpcResult(response, decode)
  eq(result.foo, "bar")
end)

test("returns nil when result is absent", function()
  local result = TetherUtils.unwrapRpcResult({}, decode)
  eq(result, nil)
end)

test("returns raw result when content array is empty", function()
  local response = { result = { content = {} } }
  local result = TetherUtils.unwrapRpcResult(response, decode)
  assert(result ~= nil, "should return result table, not nil")
end)

-- ── Summary ───────────────────────────────────────────────────────────────────

print(("\n%d passed, %d failed"):format(passed, failed))

if failed > 0 then
  process.exit(1)
end
