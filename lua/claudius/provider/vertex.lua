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

  -- Schedule deletion of the temporary file after 60 seconds as a safety measure
  -- This ensures the file is deleted even if there's an unhandled error
  vim.defer_fn(function()
    if vim.fn.filereadable(tmp_file) == 1 then
      log.debug("Safety timer: removing temporary service account file")
      os.remove(tmp_file)
    end
  end, 60 * 1000) -- 60 seconds in milliseconds

  -- First check if gcloud is installed
  local check_cmd = "command -v gcloud >/dev/null 2>&1"
  local check_result = os.execute(check_cmd)

  if check_result ~= 0 then
    -- Clean up the temporary file
    os.remove(tmp_file)
    return nil,
      "gcloud command not found. Please install the Google Cloud CLI or set VERTEX_AI_ACCESS_TOKEN environment variable."
  end

  -- Use gcloud to generate an access token
  -- Capture both stdout and stderr for better error reporting
  local cmd = string.format("GOOGLE_APPLICATION_CREDENTIALS=%s gcloud auth print-access-token 2>&1", tmp_file)
  local handle = io.popen(cmd)
  local output = nil
  local token = nil
  local err = nil

  if handle then
    output = handle:read("*a")
    local success, _, code = handle:close()

    -- Clean up the temporary file immediately after use
    os.remove(tmp_file)

    if success and output and #output > 0 then
      -- Check if the output looks like a token (no error messages)
      if
        not output:match("ERROR:")
        and not output:match("command not found")
        and not output:match("not recognized")
      then
        -- Trim whitespace
        token = output:gsub("%s+$", "")
        -- Basic validation: tokens are usually long strings without spaces
        if #token > 20 and not token:match("%s") then
          return token
        else
          err = "Invalid token format received from gcloud"
          log.debug("Invalid token format: " .. output)
        end
      else
        -- This is an error message from gcloud
        err = "gcloud error: " .. output
        log.debug("gcloud command output: " .. output)
      end
    else
      err = "Failed to generate access token (exit code: " .. tostring(code) .. ")"
      if output and #output > 0 then
        err = err .. "\nOutput: " .. output
        log.debug("gcloud command output: " .. output)
      end
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
  
  -- Ensure we have a valid model name
  if not provider.model then
    provider.model = "gemini-1.5-flash"
  end

  -- Set the API version
  provider.api_version = "v1"
  
  -- Initialize response accumulator for multi-line responses
  provider.response_accumulator = {
    lines = {},
    has_processed_content = false
  }
  
  -- Reset the accumulator before each request
  vim.api.nvim_create_autocmd("User", {
    pattern = "ClaudiusBeforeRequest",
    callback = function()
      provider.response_accumulator = {
        lines = {},
        has_processed_content = false
      }
    end
  })

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
      if err then
        error(
          err
            .. "\n\n---\n\nVertex AI requires the Google Cloud CLI (gcloud) to generate access tokens from service accounts.\n"
            .. "Please install gcloud or set VERTEX_AI_ACCESS_TOKEN environment variable."
        )
      else
        error(
          "Vertex AI requires the Google Cloud CLI (gcloud) to generate access tokens from service accounts.\n"
            .. "Please install gcloud or set VERTEX_AI_ACCESS_TOKEN environment variable."
        )
      end
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
        content = msg.content:gsub("%s+$", ""),
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
        { text = msg.content },
      },
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

  -- Ensure we're requesting a stream response
  request_body.stream = true

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

  -- Ensure we're using the streamGenerateContent endpoint with SSE format
  local endpoint = string.format(
    "https://%s-aiplatform.googleapis.com/%s/projects/%s/locations/%s/publishers/google/models/%s:streamGenerateContent?alt=sse",
    self.location,
    self.api_version,
    self.project_id,
    self.location,
    self.model
  )

  log.debug("Using Vertex AI endpoint: " .. endpoint)
  return endpoint
end

-- Check accumulated response for multi-line JSON responses
function M.check_accumulated_response(self, callbacks)
  -- If we have accumulated lines, try to parse them as a complete JSON response
  if #self.response_accumulator.lines == 0 then
    return false
  end
  
  log.debug("Checking accumulated response with " .. #self.response_accumulator.lines .. " lines")
  
  -- Join all accumulated lines
  local full_response = table.concat(self.response_accumulator.lines, "\n")
  
  -- Try to parse as JSON
  local ok, data = pcall(vim.fn.json_decode, full_response)
  if not ok then
    log.debug("Failed to parse accumulated response as JSON")
    return false
  end
  
  -- Check if it's an array response with error
  if vim.tbl_islist(data) and #data > 0 and type(data[1]) == "table" and data[1].error then
    local error_data = data[1]
    local msg = "Vertex AI API error"
    
    if error_data.error then
      if error_data.error.message then
        msg = error_data.error.message
      end
      
      if error_data.error.status then
        msg = msg .. " (Status: " .. error_data.error.status .. ")"
      end
      
      -- Include details if available
      if error_data.error.details and #error_data.error.details > 0 then
        for _, detail in ipairs(error_data.error.details) do
          if detail["@type"] and detail["@type"]:match("BadRequest") and detail.fieldViolations then
            for _, violation in ipairs(detail.fieldViolations) do
              if violation.description then
                msg = msg .. "\n" .. violation.description
              end
            end
          end
        end
      end
    end
    
    log.error("Parsed error from accumulated response: " .. msg)
    
    if callbacks.on_error then
      callbacks.on_error(msg)
    end
    return true
  end
  
  -- Check for direct error object
  if type(data) == "table" and data.error then
    local msg = "Vertex AI API error"
    if data.error.message then
      msg = data.error.message
    end
    
    log.error("Parsed error from accumulated response: " .. msg)
    
    if callbacks.on_error then
      callbacks.on_error(msg)
    end
    return true
  end
  
  return false
end

-- Process a response line from Vertex AI API (Server-Sent Events format)
function M.process_response_line(self, line, callbacks)
  -- Skip empty lines
  if not line or line == "" then
    return
  end

  -- Check for expected format: lines should start with "data: "
  if not line:match("^data: ") then
    -- This is not a standard SSE data line
    log.debug("Non-SSE line from Vertex AI, adding to accumulator: " .. line)
    
    -- Add to response accumulator for potential multi-line JSON response
    table.insert(self.response_accumulator.lines, line)
    
    -- Try parsing as a direct JSON error response (for single-line errors)
    local ok, error_data = pcall(vim.fn.json_decode, line)
    if ok and error_data.error then
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

    -- If we can't parse it as an error, continue accumulating
    return
  end

  -- Extract JSON from data: prefix
  local json_str = line:gsub("^data: ", "")
  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    log.error("Failed to parse JSON from Vertex AI response: " .. json_str)
    return
  end

  -- Validate the response structure
  if type(data) ~= "table" then
    log.error("Expected table in Vertex AI response, got: " .. type(data))
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

  -- Process usage information if available
  if data.usageMetadata then
    local usage = data.usageMetadata
    
    -- Handle input tokens
    if usage.promptTokenCount and callbacks.on_usage then
      callbacks.on_usage({
        type = "input",
        tokens = usage.promptTokenCount,
      })
    end
    
    -- Handle output tokens
    if usage.candidatesTokenCount and callbacks.on_usage then
      callbacks.on_usage({
        type = "output",
        tokens = usage.candidatesTokenCount,
      })
    end
    
    -- Check if this is the final message with finish reason
    if data.candidates and data.candidates[1] and data.candidates[1].finishReason then
      log.debug("Received finish reason: " .. tostring(data.candidates[1].finishReason))
      
      -- Signal message completion
      if callbacks.on_message_complete then
        callbacks.on_message_complete()
      end
      
      -- Signal done
      if callbacks.on_done then
        callbacks.on_done()
      end
      return
    end
  end

  -- Handle content
  if data.candidates and data.candidates[1] and data.candidates[1].content then
    local content = data.candidates[1].content
    
    -- Check if there's text content
    if content.parts and content.parts[1] and content.parts[1].text then
      local text = content.parts[1].text
      log.debug("Content text: " .. text)
      
      -- Mark that we've received valid content
      self.response_accumulator.has_processed_content = true
      
      if callbacks.on_content then
        callbacks.on_content(text)
      end
    end
  end
end

-- Check unprocessed JSON responses (called by base provider on_exit)
function M.check_unprocessed_json(self, callbacks)
  -- Check accumulated response if we haven't processed any content
  if not self.response_accumulator.has_processed_content and #self.response_accumulator.lines > 0 then
    if not self:check_accumulated_response(callbacks) then
      log.debug("No actionable content found in accumulated response")
    end
  end
  
  -- Reset the accumulator for next request
  self.response_accumulator = {
    lines = {},
    has_processed_content = false
  }
end

return M
