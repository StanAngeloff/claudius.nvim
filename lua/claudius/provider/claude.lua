--- Claude provider for Claudius
--- Implements the Claude API integration
local base = require("claudius.provider.base")
local log = require("claudius.logging")
local M = {}

-- Create a new Claude provider instance
function M.new(opts)
  local provider = base.new(opts)

  -- Claude-specific state
  provider.endpoint = "https://api.anthropic.com/v1/messages"
  provider.api_version = "2023-06-01"

  -- Set metatable to use Claude methods
  return setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
end

-- Get API key from environment, keyring, or prompt
function M.get_api_key(self)
  -- Call the base implementation with Claude-specific parameters
  return require("claudius.provider.base").get_api_key(self, {
    env_var_name = "ANTHROPIC_API_KEY",
    keyring_service_name = "anthropic",
    keyring_key_name = "api",
  })
end

-- Format messages for Claude API
function M.format_messages(self, messages, system_message)
  local formatted = {}

  for _, msg in ipairs(messages) do
    local role = msg.type == "You" and "user" or msg.type == "Assistant" and "assistant" or nil

    if role then
      table.insert(formatted, {
        role = role,
        content = msg.content:gsub("%s+$", ""),
      })
    end
  end

  return formatted, system_message
end

-- Create request body for Claude API
function M.create_request_body(self, formatted_messages, system_message, opts)
  local request_body = {
    model = opts.model or self.options.model,
    messages = formatted_messages,
    system = system_message,
    max_tokens = opts.max_tokens or self.options.parameters.max_tokens,
    temperature = opts.temperature or self.options.parameters.temperature,
    stream = true,
  }

  return request_body
end

-- Get request headers for Claude API
function M.get_request_headers(self)
  local api_key = self:get_api_key()
  return {
    "x-api-key: " .. api_key,
    "anthropic-version: " .. self.api_version,
    "content-type: application/json",
  }
end

-- Get API endpoint
function M.get_endpoint(self)
  return self.endpoint
end

-- Process a response line from Claude API
function M.process_response_line(self, line, callbacks)
  -- Skip empty lines
  if not line or line == "" then
    return
  end

  -- First try parsing the line directly as JSON for error responses
  local ok, error_data = pcall(vim.fn.json_decode, line)
  if ok and error_data.type == "error" then
    local msg = "Claude API error"
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
    log.error("Unexpected response format from Claude API: " .. line)
    
    -- Try parsing as a direct JSON error response again (more thorough check)
    local parse_ok, error_json = pcall(vim.fn.json_decode, line)
    if parse_ok and type(error_json) == "table" and error_json.error then
      local msg = "Claude API error"
      if error_json.error.message then
        msg = error_json.error.message
      end
      
      log.error("API error in unexpected format: " .. msg)
      
      if callbacks.on_error then
        callbacks.on_error(msg)
      end
      return
    end
    
    -- If we can't parse it as an error, log and ignore
    log.error("Ignoring unrecognized Claude API response line")
    return
  end

  -- Extract JSON from data: prefix
  local json_str = line:gsub("^data: ", "")
  
  -- Handle [DONE] message
  if json_str == "[DONE]" then
    log.debug("Received [DONE] message from Claude API")
    
    if callbacks.on_done then
      callbacks.on_done()
    end
    return
  end

  -- Parse the JSON data
  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    log.error("Failed to parse JSON from Claude API response: " .. json_str)
    return
  end

  -- Validate the response structure
  if type(data) ~= "table" then
    log.error("Expected table in Claude API response, got: " .. type(data))
    return
  end

  -- Handle error responses
  if data.type == "error" then
    local msg = "Claude API error"
    if data.error and data.error.message then
      msg = data.error.message
    end
    
    log.error("API error in response: " .. msg)
    
    if callbacks.on_error then
      callbacks.on_error(msg)
    end
    return
  end

  -- Track usage information
  if data.type == "message_start" then
    log.debug("Received message_start event")
    -- Get input tokens from message.usage in message_start event
    if data.message and data.message.usage and data.message.usage.input_tokens then
      if callbacks.on_usage then
        callbacks.on_usage({
          type = "input",
          tokens = data.message.usage.input_tokens,
        })
      end
    else
      log.error("Expected usage information in message_start event but not found")
    end
  end

  -- Track output tokens from usage field in any event
  if data.usage and data.usage.output_tokens then
    if callbacks.on_usage then
      callbacks.on_usage({
        type = "output",
        tokens = data.usage.output_tokens,
      })
    end
  end

  -- Handle message_stop event
  if data.type == "message_stop" then
    log.debug("Received message_stop event")
    if callbacks.on_message_complete then
      callbacks.on_message_complete()
    end
  end

  -- Handle content blocks
  if data.type == "content_block_delta" then
    if data.delta and data.delta.text then
      log.debug("Content delta: " .. data.delta.text)
      
      if callbacks.on_content then
        callbacks.on_content(data.delta.text)
      end
    else
      log.error("Received content_block_delta without expected text field")
    end
  elseif data.type and data.type ~= "message_start" and data.type ~= "message_stop" then
    log.error("Received unknown event type from Claude API: " .. data.type)
  end
end

return M
