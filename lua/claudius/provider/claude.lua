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
  -- Get parameters with proper fallbacks
  local max_tokens = opts.max_tokens or self.options.parameters.max_tokens
  local temperature = opts.temperature or self.options.parameters.temperature

  local request_body = {
    model = opts.model or self.options.model,
    messages = formatted_messages,
    system = system_message,
    max_tokens = max_tokens,
    temperature = temperature,
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

  -- Check for expected format: lines should start with "event: " or "data: "
  if not (line:match("^event: ") or line:match("^data: ")) then
    -- This is not a standard SSE line
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
    log.error("Ignoring unrecognized Claude API response line: " .. line)
    return
  end

  -- Handle event lines (event: type)
  if line:match("^event: ") then
    local event_type = line:gsub("^event: ", "")
    log.debug("Received event type: " .. event_type)
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

  -- Handle ping events
  if data.type == "ping" then
    log.debug("Received ping event")
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
      log.debug("No usage information in message_start event")
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

  -- Handle message_delta event
  if data.type == "message_delta" then
    log.debug("Received message_delta event")
    -- Update usage if available
    if data.usage and data.usage.output_tokens and callbacks.on_usage then
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

    -- Also trigger on_done to ensure we clean up properly
    -- This is important when Claude returns no new content
    if callbacks.on_done then
      callbacks.on_done()
    end
  end

  -- Handle content_block_start event
  if data.type == "content_block_start" then
    log.debug("Received content_block_start event for index " .. tostring(data.index))
  end

  -- Handle content_block_stop event
  if data.type == "content_block_stop" then
    log.debug("Received content_block_stop event for index " .. tostring(data.index))
  end

  -- Handle content blocks deltas
  if data.type == "content_block_delta" then
    if not data.delta then
      log.error("Received content_block_delta without delta field")
      return
    end

    if data.delta.type == "text_delta" and data.delta.text then
      log.debug("Content text delta: " .. data.delta.text)

      if callbacks.on_content then
        callbacks.on_content(data.delta.text)
      end
    elseif data.delta.type == "input_json_delta" and data.delta.partial_json ~= nil then
      log.debug("Content input_json_delta: " .. tostring(data.delta.partial_json))
      -- Tool use JSON deltas are not displayed directly
    elseif data.delta.type == "thinking_delta" and data.delta.thinking then
      log.debug("Content thinking delta: " .. data.delta.thinking)
      -- Thinking deltas are not displayed directly
    elseif data.delta.type == "signature_delta" and data.delta.signature then
      log.debug("Content signature delta received")
      -- Signature deltas are not displayed
    else
      log.error("Received content_block_delta with unknown delta type: " .. tostring(data.delta.type))
    end
  elseif
    data.type
    and not (
      data.type == "message_start"
      or data.type == "message_stop"
      or data.type == "message_delta"
      or data.type == "content_block_start"
      or data.type == "content_block_stop"
      or data.type == "ping"
    )
  then
    log.error("Received unknown event type from Claude API: " .. data.type)
  end
end

return M
