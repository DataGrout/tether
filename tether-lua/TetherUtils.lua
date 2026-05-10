-- TetherUtils — pure helpers with no Roblox service dependencies.
-- Kept separate so they can be unit-tested without the full game environment.

local TetherUtils = {}

local INFERENCE_TOOLS = {
  ["prism.analyze"]      = true, ["prism.refract"]   = true,
  ["prism.chart"]        = true, ["prism.orient"]    = true,
  ["prism.horizon"]      = true, ["latent.expand"]   = true,
  ["latent.horizon"]     = true, ["latent.orient"]   = true,
  ["inference.invoke"]   = true, ["inference.search"] = true,
  ["inference.research"] = true, ["agents.orchestrate"] = true,
  ["agents.send"]        = true, ["warden.canary"]   = true,
  ["warden.intent"]      = true, ["warden.ensemble"] = true,
  ["warden.adjudicate"]  = true, ["toolsmith.forge"] = true,
  ["toolsmith.temper"]   = true,
}

-- Returns true if toolName refers to an inference-class tool.
-- Matches "data-grout@1/prism.analyze@1" → suite "prism.analyze".
function TetherUtils.isInferenceTool(toolName)
  local suite = toolName:match("/([%w%.]+)@")
  return suite ~= nil and INFERENCE_TOOLS[suite] == true
end

-- Unwrap the MCP content envelope returned by the gateway.
-- jsonDecode: function(string) -> table (injected to avoid Roblox service dep)
-- Returns the inner result, preferring a `result` key when present.
function TetherUtils.unwrapRpcResult(response, jsonDecode)
  local result = response.result
  if result and result.content then
    local text = result.content[1] and result.content[1].text
    if text then
      local decoded = jsonDecode(text)
      return decoded.result ~= nil and decoded.result or decoded
    end
  end
  return result
end

return TetherUtils
