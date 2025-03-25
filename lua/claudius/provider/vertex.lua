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
    return nil, "gcloud command not found. Please install the Google Cloud CLI or set VERTEX_AI_ACCESS_TOKEN environment variable."
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
      if not output:match("ERROR:") and not output:match("command not found") and not output:match("not recognized") then
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
  
  -- Set the API version
  provider.api_version = "v1"
  
  -- Initialize JSON state
  provider.accumulated_json = ""
  provider.in_array = false

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
        error(err .. "\n\n---\n\nVertex AI requires the Google Cloud CLI (gcloud) to generate access tokens from service accounts.\n" ..
              "Please install gcloud or set VERTEX_AI_ACCESS_TOKEN environment variable.")
      else
        error("Vertex AI requires the Google Cloud CLI (gcloud) to generate access tokens from service accounts.\n" ..
              "Please install gcloud or set VERTEX_AI_ACCESS_TOKEN environment variable.")
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

-- Override prepare_curl_command to add raw output option
function M.prepare_curl_command(self, tmp_file, headers, endpoint)
  local cmd = require("claudius.provider.base").prepare_curl_command(self, tmp_file, headers, endpoint)
  
  -- Add raw output option for Vertex AI to get the raw SSE response
  table.insert(cmd, 2, "--raw")
  
  return cmd
end

-- Initialize provider state
function M.init(self)
  -- Initialize state for chunked transfer encoding parsing
  self.buffer = ""
  self.current_chunk_size = nil
  self.in_json_array = false
  self.partial_json = nil
end

-- Check for unprocessed data at the end of a response
function M.check_unprocessed_json(self)
  if self.buffer and #self.buffer > 0 then
    -- We have accumulated data that wasn't processed
    log.debug("Unprocessed buffer data at end of response: " .. self.buffer)
    
    -- Reset the buffer
    self.buffer = ""
    self.current_chunk_size = nil
  end
  
  -- If we have partial JSON, log it
  if self.partial_json then
    log.debug("Unprocessed partial JSON at end of response: " .. self.partial_json)
    self.partial_json = nil
  end
  
  -- Reset array state
  self.in_json_array = false
end

-- Process a response line from Vertex AI API (chunked transfer encoding)
function M.process_response_line(self, line, callbacks)
  -- Initialize state if not already done
  if self.buffer == nil then
    self:init()
  end

  -- Skip empty lines
  if not line or line == "" then
    return
  end

  -- Log the raw line for debugging (truncate if too long)
  if #line > 100 then
    log.debug("Processing chunk line: " .. line:sub(1, 100) .. "... (" .. #line .. " bytes)")
  else
    log.debug("Processing chunk line: " .. line)
  end

  -- First try to parse the line as a direct JSON error response
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

  -- Append the current line to our buffer
  self.buffer = self.buffer .. line

  -- Process the buffer as chunked transfer encoding data
  self:process_chunked_buffer(callbacks)
end

-- Process the chunked transfer encoding buffer
function M.process_chunked_buffer(self, callbacks)
  -- Process as much of the buffer as we can
  while #self.buffer > 0 do
    -- If we don't have a chunk size yet, try to parse it
    if not self.current_chunk_size then
      -- Look for a hexadecimal number followed by \r\n
      local hex_size = self.buffer:match("^([0-9a-fA-F]+)\r\n")
      if not hex_size then
        -- Not enough data yet, wait for more
        return
      end

      -- Convert hex to decimal
      self.current_chunk_size = tonumber(hex_size, 16)
      log.debug("Found chunk size: " .. hex_size .. " (" .. self.current_chunk_size .. " bytes)")

      -- Remove the size and \r\n from the buffer
      self.buffer = self.buffer:sub(#hex_size + 3)
      
      -- Check for end of response (chunk size 0)
      if self.current_chunk_size == 0 then
        log.debug("End of chunked response")
        self.buffer = self.buffer:sub(3) -- Skip the final \r\n
        self.current_chunk_size = nil
        
        -- Signal completion if we have callbacks
        if callbacks.on_done then
          callbacks.on_done()
        end
        
        return
      end
    end

    -- Check if we have enough data in the buffer (chunk + \r\n)
    if #self.buffer < self.current_chunk_size + 2 then
      -- Not enough data yet, wait for more
      return
    end

    -- Extract the data chunk
    local data_chunk = self.buffer:sub(1, self.current_chunk_size)
    
    -- The chunk should be followed by \r\n
    if self.buffer:sub(self.current_chunk_size + 1, self.current_chunk_size + 2) ~= "\r\n" then
      log.error("Chunk not followed by \\r\\n, found: " .. 
                self.buffer:sub(self.current_chunk_size + 1, self.current_chunk_size + 2))
    end

    -- Remove the data chunk and \r\n from the buffer
    self.buffer = self.buffer:sub(self.current_chunk_size + 3)
    
    -- Reset the chunk size for the next chunk
    self.current_chunk_size = nil

    -- Process the data chunk
    self:process_data_chunk(data_chunk, callbacks)
  end
end

-- Process a single data chunk from the chunked stream
function M.process_data_chunk(self, data_chunk, callbacks)
  -- Skip empty chunks
  if not data_chunk or data_chunk == "" then
    return
  end

  -- Log the data chunk for debugging (truncate if too long)
  if #data_chunk > 100 then
    log.debug("Processing data chunk: " .. data_chunk:sub(1, 100) .. "... (" .. #data_chunk .. " bytes)")
  else
    log.debug("Processing data chunk: " .. data_chunk)
  end

  -- Handle JSON array markers and elements
  if data_chunk == "[" then
    -- Start of JSON array
    log.debug("Starting JSON array")
    self.in_json_array = true
    return
  elseif data_chunk == "]" then
    -- End of JSON array
    log.debug("Ending JSON array")
    self.in_json_array = false
    return
  elseif data_chunk == "," then
    -- Comma separator between array elements
    log.debug("Found JSON array element separator")
    return
  end

  -- Try to parse the chunk as a JSON object
  local ok, data = pcall(vim.fn.json_decode, data_chunk)
  if ok and type(data) == "table" then
    -- Successfully parsed a JSON object
    log.debug("Successfully parsed JSON object")
    
    -- Process the object
    self:process_response_object(data, callbacks)
  else
    -- Not a valid JSON object, might be a partial object
    -- Just log it for now - we can't do much with partial JSON
    log.debug("Received non-JSON or partial JSON: " .. data_chunk)
    self.partial_json = data_chunk
  end
end

-- Process a parsed response object
function M.process_response_object(self, data, callbacks)
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
    log.debug("Received usage metadata: " .. vim.inspect(data.usageMetadata))
    
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
    
    -- If we have usage metadata and a finish reason, this is the final response
    if data.candidates and #data.candidates > 0 and 
       data.candidates[1].finishReason and 
       data.candidates[1].finishReason ~= vim.NIL and 
       data.candidates[1].finishReason ~= nil then
      
      log.debug("Final response with usage metadata received")
      
      -- Signal message completion
      if callbacks.on_message_complete then
        callbacks.on_message_complete()
      end
    end
  end

  -- Handle content
  if data.candidates and #data.candidates > 0 then
    local candidate = data.candidates[1]
    
    -- Check for finish reason
    if candidate.finishReason and 
       candidate.finishReason ~= vim.NIL and 
       candidate.finishReason ~= nil then
      
      log.debug("Received finish reason: " .. tostring(candidate.finishReason))
      
      -- Signal message completion if this is the final chunk
      if callbacks.on_message_complete then
        callbacks.on_message_complete()
      end
    end
    
    -- Process content
    if candidate.content and 
       candidate.content.parts and 
       #candidate.content.parts > 0 then
      
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
