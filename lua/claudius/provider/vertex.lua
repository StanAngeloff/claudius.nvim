--- Google Vertex AI provider for Claudius
--- Implements the Google Vertex AI API integration
local openai = require("claudius.provider.openai")
local log = require("claudius.logging")
local M = {}

-- Create a new Google Vertex AI provider instance
function M.new(opts)
  local provider = openai.new(opts)

  -- Vertex AI-specific state
  -- First check for top-level parameters.vertex, then fall back to top-level vertex
  local vertex_opts = (opts.parameters and opts.parameters.vertex) or opts.vertex or {}
  
  -- Get project_id from parameters.vertex, parameters, or vertex
  provider.project_id = vertex_opts.project_id or 
                        (opts.parameters and opts.parameters.project_id)
  
  -- Get location from parameters.vertex, parameters, or vertex, with default
  provider.location = vertex_opts.location or 
                      (opts.parameters and opts.parameters.location) or 
                      "europe-central2-aiplatform"
  
  -- Get endpoint_id from parameters.vertex, parameters, or vertex
  provider.endpoint_id = vertex_opts.endpoint_id or 
                         (opts.parameters and opts.parameters.endpoint_id)

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
    keyring_project_id = self.project_id,
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
