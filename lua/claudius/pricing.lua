local M = {}

-- Pricing information for Claude models (USD per million tokens)
M.models = {
  ["claude-3-5-sonnet-20241022"] = {
    input = 3.0,   -- $3 per million input tokens
    output = 15.0  -- $15 per million output tokens
  }
}

-- Calculate cost for tokens
function M.calculate_cost(model, input_tokens, output_tokens)
  local pricing = M.models[model]
  if not pricing then
    return nil
  end
  
  -- Calculate costs (per million tokens)
  local input_cost = (input_tokens / 1000000) * pricing.input
  local output_cost = (output_tokens / 1000000) * pricing.output
  
  -- Round to 2 decimal places
  return {
    input = math.ceil(input_cost * 100) / 100,
    output = math.ceil(output_cost * 100) / 100,
    total = math.ceil((input_cost + output_cost) * 100) / 100
  }
end

return M
