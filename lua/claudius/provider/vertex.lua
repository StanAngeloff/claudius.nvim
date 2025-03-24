--- Google Vertex AI provider for Claudius
--- Implements the Google Vertex AI API integration
local base = require("claudius.provider.base")
local log = require("claudius.logging")
local M = {}

-- Utility function to generate access token from service account JSON
local function generate_access_token(service_account_json)
  -- Create a temporary file with the service account JSON
  local tmp_file = os.tmpname()
  local f = io.open(tmp_file, "w")
  if not f then
    return nil, "Failed to create temporary file for service account"
  end
  f:write(service_account_json)
  f:close()

  -- Use gcloud to generate an access token
  local cmd = string.format("GOOGLE_APPLICATION_CREDENTIALS=%s gcloud auth print-access-token 2>/dev/null", tmp_file)
  local handle = io.popen(cmd)
  local token = nil
  local err = nil
  
  if handle then
    token = handle:read("*a")
    local success, _, code = handle:close()
    
    -- Clean up the temporary file
    os.remove(tmp_file)
    
    if success and token and #token > 0 then
      -- Trim whitespace
      token = token:gsub("%s+$", "")
      return token
    else
      err = "Failed to generate access token (exit code: " .. tostring(code) .. ")"
    end
  else
    -- Clean up the temporary file
    os.remove(tmp_file)
    err = "Failed to execute gcloud command"
  end
  
  return nil, err
end

-- Create a new Google Vertex AI provider instance
function M.new(opts)
  local provider = base.new(opts)

  -- Vertex AI-specific state
  -- Get parameters with defaults, then override with vertex-specific parameters
  local params = opts.parameters or {}
  local vertex_params = params.vertex or {}
  
  -- Set provider properties with defaults
  provider.project_id = vertex_params.project_id or params.project_id
  provider.location = vertex_params.location or params.location or "us-central1"
  provider.model = opts.model or require("claudius.provider.defaults").get_model("vertex")
  
  -- Set the API version
  provider.api_version = "v1"

  -- Set metatable to use Vertex AI methods
  return setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
end

-- Get access token from environment, keyring, or prompt
function M.get_api_key(self)
  -- First try to get token from environment variable
  local token = os.getenv("VERTEX_AI_ACCESS_TOKEN")
  if token and #token > 0 then
    self.state.api_key = token
    return token
  end
  
  -- Try to get service account JSON from keyring
  local service_account_json = require("claudius.provider.base").get_api_key(self, {
    env_var_name = "VERTEX_SERVICE_ACCOUNT",
    keyring_service_name = "vertex",
    keyring_key_name = "api",
    keyring_project_id = self.project_id,
  })
  
  -- If we have service account JSON, try to generate an access token
  if service_account_json and service_account_json:match("service_account") then
    log.debug("Found service account JSON, attempting to generate access token")
    
    local token, err = generate_access_token(service_account_json)
    if token then
      log.debug("Successfully generated access token from service account")
      self.state.api_key = token
      return token
    else
      log.error("Failed to generate access token: " .. (err or "unknown error"))
      error("Vertex AI requires the Google Cloud CLI (gcloud) to generate access tokens from service accounts.\n" ..
            "Please install gcloud or set VERTEX_AI_ACCESS_TOKEN environment variable.\n\n" ..
            "Error: " .. (err or "unknown error"))
    end
  end
  
  -- If we have something but it's not a service account JSON, it might be a direct token
  if service_account_json and #service_account_json > 0 then
    self.state.api_key = service_account_json
    return service_account_json
  end
  
  return nil
end

-- Format messages for Vertex AI API
function M.format_messages(self, messages, system_message)
  local formatted = {}
  local system_content = nil

  -- Look for system message in the messages
  for _, msg in ipairs(messages) do
    if msg.type == "System" then
      system_content = msg.content:gsub("%s+$", "")
      break
    end
  end

  -- If system_message parameter is provided, it overrides any system message in messages
  if system_message then
    system_content = system_message
  end

  -- Add user and assistant messages
  for _, msg in ipairs(messages) do
    local role = nil
    if msg.type == "You" then
      role = "user"
    elseif msg.type == "Assistant" then
      role = "model"
    end

    if role then
      table.insert(formatted, {
        role = role,
        content = msg.content:gsub("%s+$", "")
      })
    end
  end

  return formatted, system_content
end

-- Create request body for Vertex AI API
function M.create_request_body(self, formatted_messages, system_message, opts)
  -- Convert formatted_messages to Vertex AI format
  local contents = {}
  for _, msg in ipairs(formatted_messages) do
    table.insert(contents, {
      role = msg.role,
      parts = {
        { text = msg.content }
      }
    })
  end

  local request_body = {
    contents = contents,
    model = opts.model or self.model,
    generationConfig = {
      maxOutputTokens = opts.max_tokens or self.options.parameters.max_tokens,
      temperature = opts.temperature or self.options.parameters.temperature,
    },
  }

  -- Add system instruction if provided
  if system_message then
    request_body.systemInstruction = {
      parts = {
        { text = system_message }
      }
    }
  end

  return request_body
end

-- Get request headers for Vertex AI API
function M.get_request_headers(self)
  local access_token = self:get_api_key()
  if not access_token then
    error("No Vertex AI access token available. Please set up a service account or provide an access token.")
  end
  
  return {
    "Authorization: Bearer " .. access_token,
    "Content-Type: application/json",
  }
end

-- Get API endpoint for Vertex AI
function M.get_endpoint(self)
  if not self.project_id then
    log.error("Vertex AI project_id is required")
    return nil
  end

  local endpoint = string.format(
    "https://%s-aiplatform.googleapis.com/%s/projects/%s/locations/%s/publishers/google/models/%s:streamGenerateContent",
    self.location,
    self.api_version,
    self.project_id,
    self.location,
    self.model
  )

  log.debug("Using Vertex AI endpoint: " .. endpoint)
  return endpoint
end

-- Process a response line from Vertex AI API
function M.process_response_line(self, line, callbacks)
  -- Skip empty lines
  if not line or line == "" then
    return
  end

  -- First try to parse the line as a JSON error response
  local ok, error_data = pcall(vim.fn.json_decode, line)
  if ok and type(error_data) == "table" and error_data.error then
    local msg = "Vertex AI API error"
    if error_data.error and error_data.error.message then
      msg = error_data.error.message
    end

    -- Log the error
    log.error("API error: " .. msg)

    if callbacks.on_error then
      callbacks.on_error(msg)
    end
    return
  end

  -- Check for expected format: lines should start with "data: "
  if not line:match("^data: ") then
    -- This is not a standard SSE data line
    log.error("Unexpected response format from Vertex AI: " .. line)

    -- If we can't parse it as an error, log and ignore
    log.error("Ignoring unrecognized response line")
    return
  end

  -- Handle [DONE] message
  if line == "data: [DONE]" then
    log.debug("Received [DONE] message")

    if callbacks.on_done then
      callbacks.on_done()
    end
    return
  end

  -- Extract JSON from data: prefix
  local json_str = line:gsub("^data: ", "")
  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    log.error("Failed to parse JSON from response: " .. json_str)
    return
  end

  -- Validate the response structure
  if type(data) ~= "table" then
    log.error("Expected table in response, got: " .. type(data))
    return
  end

  -- Handle error responses
  if data.error then
    local msg = "Vertex AI API error"
    if data.error and data.error.message then
      msg = data.error.message
    end

    log.error("API error in response: " .. msg)

    if callbacks.on_error then
      callbacks.on_error(msg)
    end
    return
  end

  -- Handle usage information
  if data.usageMetadata then
    if callbacks.on_usage and data.usageMetadata.promptTokenCount then
      callbacks.on_usage({
        type = "input",
        tokens = data.usageMetadata.promptTokenCount,
      })
    end
    if callbacks.on_usage and data.usageMetadata.candidatesTokenCount then
      callbacks.on_usage({
        type = "output",
        tokens = data.usageMetadata.candidatesTokenCount,
      })
    end
  end

  -- Handle content
  if data.candidates and #data.candidates > 0 then
    local candidate = data.candidates[1]
    
    -- Check for finish reason
    if candidate.finishReason and candidate.finishReason ~= vim.NIL and candidate.finishReason ~= nil then
      log.debug("Received finish_reason: " .. tostring(candidate.finishReason))
      
      -- Signal message completion if this is the final chunk
      if callbacks.on_message_complete then
        callbacks.on_message_complete()
      end
    end
    
    -- Process content
    if candidate.content and candidate.content.parts and #candidate.content.parts > 0 then
      for _, part in ipairs(candidate.content.parts) do
        if part.text then
          log.debug("Content text: " .. part.text)
          
          if callbacks.on_content then
            callbacks.on_content(part.text)
          end
        end
      end
    end
  end
end

return M
