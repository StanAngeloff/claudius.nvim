--- Google Vertex AI provider for Claudius
--- Implements the Google Vertex AI API integration
local openai = require("claudius.provider.openai")
local log = require("claudius.logging")
local M = {}

-- Create a new Google Vertex AI provider instance
function M.new(opts)
  local provider = openai.new(opts)

  -- Vertex AI-specific state
  provider.project_id = opts.vertex and opts.vertex.project_id
  provider.location = opts.vertex and opts.vertex.location or "europe-central2-aiplatform"
  provider.endpoint_id = opts.vertex and opts.vertex.endpoint_id

  -- Set metatable to use Vertex AI methods
  return setmetatable(provider, { __index = setmetatable(M, { __index = openai }) })
end

-- Get API key from environment, keyring, or prompt
function M.get_api_key(self)
  -- Call the base implementation with Vertex AI-specific parameters
  return require("claudius.provider.base").get_api_key(self, {
    env_var_name = "VERTEX_API_KEY",
    keyring_service_name = "vertex",
    keyring_key_name = "api",
  })
end

-- Get API endpoint for Vertex AI
function M.get_endpoint(self)
  if not self.project_id then
    log.error("Vertex AI project_id is required")
    return nil
  end

  if not self.endpoint_id then
    log.error("Vertex AI endpoint_id is required")
    return nil
  end

  local endpoint = string.format(
    "https://%s-aiplatform.googleapis.com/v1beta1/projects/%s/locations/%s/endpoints/%s/chat/completions",
    self.location,
    self.project_id,
    self.location,
    self.endpoint_id
  )
  
  log.debug("Using Vertex AI endpoint: " .. endpoint)
  return endpoint
end

-- Get request headers for Vertex AI API
function M.get_request_headers(self)
  local api_key = self:get_api_key()
  return {
    "x-goog-api-key: " .. api_key,
    "Content-Type: application/json",
  }
end

return M
