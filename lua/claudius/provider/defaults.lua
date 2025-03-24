--- Claudius provider defaults
--- Centralized configuration for provider-specific defaults
local M = {}

-- Default models for each provider
M.models = {
  claude = "claude-3-7-sonnet-20250219",
  openai = "gpt-4o",
}

-- Default parameters for all providers
M.parameters = {
  max_tokens = 4000,
  temperature = 0.7,
}

-- Get the default model for a provider
function M.get_model(provider_name)
  return M.models[provider_name] or M.models.claude
end

-- Check if a model belongs to a specific provider
function M.is_provider_model(model_name, provider_name)
  if provider_name == "claude" then
    return model_name:match("^claude") ~= nil
  elseif provider_name == "openai" then
    return model_name:match("^gpt") ~= nil
  end
  return false
end

-- Get the appropriate model for a provider
function M.get_appropriate_model(model_name, provider_name)
  -- If the model is appropriate for the provider, use it
  if M.is_provider_model(model_name, provider_name) then
    return model_name
  end
  
  -- Otherwise, return the default model for the provider
  return M.get_model(provider_name)
end

return M
