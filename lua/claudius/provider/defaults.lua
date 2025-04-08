--- Claudius provider defaults
--- Centralized configuration for provider-specific defaults
local M = {}

-- Default models for each provider
M.models = {
  claude = "claude-3-7-sonnet-20250219",
  openai = "gpt-4o",
  vertex = "gemini-2.0-flash-001",
}

-- Available OpenAI models
M.openai_models = {
  -- Latest models
  "gpt-4.5-preview",
  "gpt-4.5-preview-2025-02-27",
  "gpt-4o",
  "gpt-4o-2024-08-06",
  "gpt-4o-audio-preview",
  "gpt-4o-audio-preview-2024-12-17",
  "gpt-4o-realtime-preview",
  "gpt-4o-realtime-preview-2024-12-17",
  "gpt-4o-mini",
  "gpt-4o-mini-2024-07-18",
  "gpt-4o-mini-audio-preview",
  "gpt-4o-mini-audio-preview-2024-12-17",
  "gpt-4o-mini-realtime-preview",
  "gpt-4o-mini-realtime-preview-2024-12-17",
  "o1",
  "o1-2024-12-17",
  "o1-pro",
  "o1-pro-2025-03-19",
  "o3-mini",
  "o3-mini-2025-01-31",
  "o1-mini",
  "o1-mini-2024-09-12",
  "gpt-4o-mini-search-preview",
  "gpt-4o-mini-search-preview-2025-03-11",
  "gpt-4o-search-preview",
  "gpt-4o-search-preview-2025-03-11",
  "computer-use-preview",
  "computer-use-preview-2025-03-11",
  "chatgpt-4o-latest",

  -- Other models
  "gpt-4-turbo",
  "gpt-4-turbo-2024-04-09",
  "gpt-4-0125-preview",
  "gpt-4-1106-preview",
  "gpt-4-1106-vision-preview",
  "gpt-4",
  "gpt-4-0613",
  "gpt-4-0314",
  "gpt-4-32k",
  "gpt-3.5-turbo",
  "gpt-3.5-turbo-0125",
  "gpt-3.5-turbo-1106",
  "gpt-3.5-turbo-0613",
  "gpt-3.5-0301",
  "gpt-3.5-turbo-instruct",
  "gpt-3.5-turbo-16k-0613",
}

-- Available Google Vertex AI models
M.vertex_models = {
  -- Gemini 2.0 models
  "gemini-2.0-flash-001",
  "gemini-2.0-flash-lite-001",
  -- Gemini 1.5 models
  "gemini-1.5-pro-001",
  "gemini-1.5-pro-002",
  "gemini-1.5-flash-001",
  "gemini-1.5-flash-002",
  "gemini-1.5-flash-8b-001",
  -- Gemini 1.0 models
  "gemini-1.0-pro-001",
  "gemini-1.0-pro-002",
  "gemini-1.0-pro-vision-001",
  "gemini-1.0-ultra-001",
  "gemini-1.0-ultra-vision-001",
  -- PaLM models
  "text-bison",
  "chat-bison",
  "codechat-bison",
}

-- Authentication notes for providers
M.auth_notes = {
  vertex = [[
## Authentication Options

Vertex AI requires OAuth2 authentication. You can:
1. Set VERTEX_AI_ACCESS_TOKEN environment variable with a valid access token
2. Store a service account JSON in the keyring (requires gcloud CLI)
3. Set VERTEX_SERVICE_ACCOUNT environment variable with the service account JSON
]],
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
      or model_name:match("^o%d") ~= nil
      or model_name:match("^chatgpt") ~= nil
      or model_name:match("^computer%-use") ~= nil
  elseif provider_name == "vertex" then
    return model_name:match("^gemini") ~= nil
      or model_name:match("^text%-bison") ~= nil
      or model_name:match("^chat%-bison") ~= nil
      or model_name:match("^codechat%-bison") ~= nil
      or model_name:match("^text%-embedding") ~= nil
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
