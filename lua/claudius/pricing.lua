--- Claudius pricing functionality
local M = {}

-- Pricing information for models (USD per million tokens)
M.models = {
  -- Claude models
  ["claude-3-5-sonnet"] = {
    input = 3.0, -- $3 per million input tokens
    output = 15.0, -- $15 per million output tokens
  },
  ["claude-3-7-sonnet"] = {
    input = 3.0, -- $3 per million input tokens
    output = 15.0, -- $15 per million output tokens
  },

  -- Vertex AI models (Gemini)
  ["gemini-2.0-flash-001"] = {
    input = 0.10, -- $0.10 per million input tokens (text/image/video)
    output = 0.40, -- $0.40 per million output tokens
  },
  ["gemini-2.0-flash-lite-001"] = {
    input = 0.075, -- $0.075 per million input tokens
    output = 0.30, -- $0.30 per million output tokens
  },
  ["gemini-1.5-pro-001"] = {
    input = 1.25, -- $1.25 per million input tokens (standard context <= 128k)
    output = 5.00, -- $5.00 per million output tokens (standard context <= 128k)
  },
  ["gemini-1.5-flash-001"] = {
    input = 0.075, -- $0.075 per million input tokens (standard context <= 128k)
    output = 0.30, -- $0.30 per million output tokens (standard context <= 128k)
  },
  ["gemini-1.5-flash-8b-001"] = {
    input = 0.0375, -- $0.0375 per million input tokens (standard context <= 128k)
    output = 0.15, -- $0.15 per million output tokens (standard context <= 128k)
  },
  ["gemini-1.0-pro-001"] = {
    input = 0.00125, -- $0.00125 per million input tokens
    output = 0.00375, -- $0.00375 per million output tokens
  },
  ["gemini-1.0-pro-vision-001"] = {
    input = 0.00125, -- $0.00125 per million input tokens
    output = 0.00375, -- $0.00375 per million output tokens
  },
  ["gemini-1.0-ultra-001"] = {
    input = 0.01875, -- $0.01875 per million input tokens
    output = 0.0563, -- $0.0563 per million output tokens
  },
  ["gemini-1.0-ultra-vision-001"] = {
    input = 0.01875, -- $0.01875 per million input tokens
    output = 0.0563, -- $0.0563 per million output tokens
  },

  -- OpenAI models
  ["gpt-4.5-preview"] = {
    input = 75.0, -- $75 per million input tokens
    output = 150.0, -- $150 per million output tokens
  },
  ["gpt-4.5-preview-2025-02-27"] = {
    input = 75.0, -- $75 per million input tokens
    output = 150.0, -- $150 per million output tokens
  },
  ["gpt-4o"] = {
    input = 2.5, -- $2.50 per million input tokens
    output = 10.0, -- $10 per million output tokens
  },
  ["gpt-4o-2024-08-06"] = {
    input = 2.5, -- $2.50 per million input tokens
    output = 10.0, -- $10 per million output tokens
  },
  ["gpt-4o-audio-preview"] = {
    input = 2.5, -- $2.50 per million input tokens
    output = 10.0, -- $10 per million output tokens
  },
  ["gpt-4o-audio-preview-2024-12-17"] = {
    input = 2.5, -- $2.50 per million input tokens
    output = 10.0, -- $10 per million output tokens
  },
  ["gpt-4o-realtime-preview"] = {
    input = 5.0, -- $5 per million input tokens
    output = 20.0, -- $20 per million output tokens
  },
  ["gpt-4o-realtime-preview-2024-12-17"] = {
    input = 5.0, -- $5 per million input tokens
    output = 20.0, -- $20 per million output tokens
  },
  ["gpt-4o-mini"] = {
    input = 0.15, -- $0.15 per million input tokens
    output = 0.60, -- $0.60 per million output tokens
  },
  ["gpt-4o-mini-2024-07-18"] = {
    input = 0.15, -- $0.15 per million input tokens
    output = 0.60, -- $0.60 per million output tokens
  },
  ["gpt-4o-mini-audio-preview"] = {
    input = 0.15, -- $0.15 per million input tokens
    output = 0.60, -- $0.60 per million output tokens
  },
  ["gpt-4o-mini-audio-preview-2024-12-17"] = {
    input = 0.15, -- $0.15 per million input tokens
    output = 0.60, -- $0.60 per million output tokens
  },
  ["gpt-4o-mini-realtime-preview"] = {
    input = 0.60, -- $0.60 per million input tokens
    output = 2.40, -- $2.40 per million output tokens
  },
  ["gpt-4o-mini-realtime-preview-2024-12-17"] = {
    input = 0.60, -- $0.60 per million input tokens
    output = 2.40, -- $2.40 per million output tokens
  },
  ["o1"] = {
    input = 15.0, -- $15 per million input tokens
    output = 60.0, -- $60 per million output tokens
  },
  ["o1-2024-12-17"] = {
    input = 15.0, -- $15 per million input tokens
    output = 60.0, -- $60 per million output tokens
  },
  ["o1-pro"] = {
    input = 150.0, -- $150 per million input tokens
    output = 600.0, -- $600 per million output tokens
  },
  ["o1-pro-2025-03-19"] = {
    input = 150.0, -- $150 per million input tokens
    output = 600.0, -- $600 per million output tokens
  },
  ["o3-mini"] = {
    input = 1.10, -- $1.10 per million input tokens
    output = 4.40, -- $4.40 per million output tokens
  },
  ["o3-mini-2025-01-31"] = {
    input = 1.10, -- $1.10 per million input tokens
    output = 4.40, -- $4.40 per million output tokens
  },
  ["o1-mini"] = {
    input = 1.10, -- $1.10 per million input tokens
    output = 4.40, -- $4.40 per million output tokens
  },
  ["o1-mini-2024-09-12"] = {
    input = 1.10, -- $1.10 per million input tokens
    output = 4.40, -- $4.40 per million output tokens
  },
  ["gpt-4o-mini-search-preview"] = {
    input = 0.15, -- $0.15 per million input tokens
    output = 0.60, -- $0.60 per million output tokens
  },
  ["gpt-4o-mini-search-preview-2025-03-11"] = {
    input = 0.15, -- $0.15 per million input tokens
    output = 0.60, -- $0.60 per million output tokens
  },
  ["gpt-4o-search-preview"] = {
    input = 2.50, -- $2.50 per million input tokens
    output = 10.0, -- $10 per million output tokens
  },
  ["gpt-4o-search-preview-2025-03-11"] = {
    input = 2.50, -- $2.50 per million input tokens
    output = 10.0, -- $10 per million output tokens
  },
  ["computer-use-preview"] = {
    input = 3.0, -- $3 per million input tokens
    output = 12.0, -- $12 per million output tokens
  },
  ["computer-use-preview-2025-03-11"] = {
    input = 3.0, -- $3 per million input tokens
    output = 12.0, -- $12 per million output tokens
  },
  ["chatgpt-4o-latest"] = {
    input = 5.0, -- $5 per million input tokens
    output = 15.0, -- $15 per million output tokens
  },
  ["gpt-4-turbo"] = {
    input = 10.0, -- $10 per million input tokens
    output = 30.0, -- $30 per million output tokens
  },
  ["gpt-4-turbo-2024-04-09"] = {
    input = 10.0, -- $10 per million input tokens
    output = 30.0, -- $30 per million output tokens
  },
  ["gpt-4-0125-preview"] = {
    input = 10.0, -- $10 per million input tokens
    output = 30.0, -- $30 per million output tokens
  },
  ["gpt-4-1106-preview"] = {
    input = 10.0, -- $10 per million input tokens
    output = 30.0, -- $30 per million output tokens
  },
  ["gpt-4-1106-vision-preview"] = {
    input = 10.0, -- $10 per million input tokens
    output = 30.0, -- $30 per million output tokens
  },
  ["gpt-4"] = {
    input = 30.0, -- $30 per million input tokens
    output = 60.0, -- $60 per million output tokens
  },
  ["gpt-4-0613"] = {
    input = 30.0, -- $30 per million input tokens
    output = 60.0, -- $60 per million output tokens
  },
  ["gpt-4-0314"] = {
    input = 30.0, -- $30 per million input tokens
    output = 60.0, -- $60 per million output tokens
  },
  ["gpt-4-32k"] = {
    input = 60.0, -- $60 per million input tokens
    output = 120.0, -- $120 per million output tokens
  },
  ["gpt-3.5-turbo"] = {
    input = 0.50, -- $0.50 per million input tokens
    output = 1.50, -- $1.50 per million output tokens
  },
  ["gpt-3.5-turbo-0125"] = {
    input = 0.50, -- $0.50 per million input tokens
    output = 1.50, -- $1.50 per million output tokens
  },
  ["gpt-3.5-turbo-1106"] = {
    input = 1.0, -- $1 per million input tokens
    output = 2.0, -- $2 per million output tokens
  },
  ["gpt-3.5-turbo-0613"] = {
    input = 1.50, -- $1.50 per million input tokens
    output = 2.0, -- $2 per million output tokens
  },
  ["gpt-3.5-0301"] = {
    input = 1.50, -- $1.50 per million input tokens
    output = 2.0, -- $2 per million output tokens
  },
  ["gpt-3.5-turbo-instruct"] = {
    input = 1.50, -- $1.50 per million input tokens
    output = 2.0, -- $2 per million output tokens
  },
  ["gpt-3.5-turbo-16k-0613"] = {
    input = 3.0, -- $3 per million input tokens
    output = 4.0, -- $4 per million output tokens
  },
}

-- Find the closest matching model name
local function find_matching_model(model_name)
  -- Try exact match first
  if M.models[model_name] then
    return model_name
  end

  -- Split the model name by both - and . delimiters
  local parts = {}
  for part in model_name:gmatch("[^-%.]+") do
    table.insert(parts, part)
  end

  -- Try progressively shorter combinations from the start
  local current = parts[1] -- Start with "claude"
  for i = 2, #parts do
    current = current .. "-" .. parts[i]
    if M.models[current] then
      return current
    end
  end

  return nil
end

-- Calculate cost for tokens
function M.calculate_cost(model, input_tokens, output_tokens)
  local matching_model = find_matching_model(model)
  if not matching_model then
    return nil
  end

  local pricing = M.models[matching_model]

  -- Calculate costs (per million tokens)
  local input_cost = (input_tokens / 1000000) * pricing.input
  local output_cost = (output_tokens / 1000000) * pricing.output

  -- Round to 2 decimal places
  return {
    input = math.ceil(input_cost * 100) / 100,
    output = math.ceil(output_cost * 100) / 100,
    total = math.ceil((input_cost + output_cost) * 100) / 100,
  }
end

return M
