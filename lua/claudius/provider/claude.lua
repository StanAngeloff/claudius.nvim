--- Claude provider for Claudius
--- Implements the Claude API integration
local base = require("claudius.provider.base")
local log = require("claudius.logging")
local M = {}

-- Create a new Claude provider instance
function M.new(merged_config)
  local provider = base.new(merged_config) -- Pass the already merged config to base

  -- Claude-specific state (endpoint, version)
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
function M.create_request_body(self, formatted_messages, system_message)
  -- Access parameters directly from self.parameters
  local max_tokens = self.parameters.max_tokens
  local temperature = self.parameters.temperature

  local request_body = {
    model = self.parameters.model, -- Model is already directly in self.parameters
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
    log.error("claude.process_response_line(): Claude API error: " .. log.inspect(msg))

    if callbacks.on_error then
      callbacks.on_error(msg) -- Keep original message for user notification
    end
    return
  end

  -- Check for expected format: lines should start with "event: " or "data: "
  if not (line:match("^event: ") or line:match("^data: ")) then
    -- This is not a standard SSE line or potentially a non-SSE JSON error
    log.debug("claude.process_response_line(): Received non-SSE line: " .. line)

    -- Try parsing as a direct JSON error response
    local parse_ok, error_json = pcall(vim.fn.json_decode, line)
    if parse_ok and type(error_json) == "table" and error_json.error then
      local msg = "Claude API error"
      if error_json.error.message then
        msg = error_json.error.message
      end

      log.error("claude.process_response_line(): ... Claude API error (parsed from non-SSE line): " .. log.inspect(msg))

      if callbacks.on_error then
        callbacks.on_error(msg) -- Keep original message for user notification
      end
      return
    end

    -- If we can't parse it as an error, log and ignore
    log.error("claude.process_response_line(): Ignoring unrecognized Claude API response line: " .. line)
    return
  end

  -- Handle event lines (event: type)
  if line:match("^event: ") then
    local event_type = line:gsub("^event: ", "")
    log.debug("claude.process_response_line(): Received event type: " .. event_type)
    return
  end

  -- Extract JSON from data: prefix
  local json_str = line:gsub("^data: ", "")

  -- Handle [DONE] message (Note: Claude doesn't typically send [DONE])
  if json_str == "[DONE]" then
    log.debug("claude.process_response_line(): Received [DONE] message from Claude API (unexpected)")

    if callbacks.on_done then
      callbacks.on_done()
    end
    return
  end

  -- Parse the JSON data
  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    log.error("claude.process_response_line(): Failed to parse JSON from Claude API response: " .. json_str)
    return
  end

  -- Validate the response structure
  if type(data) ~= "table" then
    log.error(
      "claude.process_response_line(): Expected table in Claude API response, got type: "
        .. type(data)
        .. ", data: "
        .. log.inspect(data)
    )
    return
  end

  -- Handle error responses
  if data.type == "error" then
    local msg = "Claude API error"
    if data.error and data.error.message then
      msg = data.error.message
    end

    log.error("claude.process_response_line(): Claude API error in response data: " .. log.inspect(msg))

    if callbacks.on_error then
      callbacks.on_error(msg) -- Keep original message for user notification
    end
    return
  end

  -- Handle ping events
  if data.type == "ping" then
    log.debug("claude.process_response_line(): Received ping event")
    return
  end

  -- Track usage information from message_start event
  if data.type == "message_start" then
    log.debug("claude.process_response_line(): Received message_start event")
    if data.message and data.message.usage and data.message.usage.input_tokens then
      log.debug(
        "claude.process_response_line(): ... Input tokens from message_start: " .. data.message.usage.input_tokens
      )
      if callbacks.on_usage then
        callbacks.on_usage({
          type = "input",
          tokens = data.message.usage.input_tokens,
        })
      end
    else
      log.debug("claude.process_response_line(): ... No usage information in message_start event")
    end
  end

  -- Track output tokens from usage field in any event (including message_delta)
  if data.usage and data.usage.output_tokens then
    log.debug("claude.process_response_line(): ... Output tokens update: " .. data.usage.output_tokens)
    if callbacks.on_usage then
      callbacks.on_usage({
        type = "output",
        tokens = data.usage.output_tokens,
      })
    end
  end

  -- Handle message_delta event (mostly for logging the event type now)
  if data.type == "message_delta" then
    log.debug("claude.process_response_line(): Received message_delta event")
    -- Usage is handled above
  end

  -- Handle message_stop event
  if data.type == "message_stop" then
    log.debug("claude.process_response_line(): Received message_stop event")
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
    log.debug("claude.process_response_line(): Received content_block_start event for index " .. tostring(data.index))
  end

  -- Handle content_block_stop event
  if data.type == "content_block_stop" then
    log.debug("claude.process_response_line(): Received content_block_stop event for index " .. tostring(data.index))
  end

  -- Handle content_block_delta event
  if data.type == "content_block_delta" then
    if not data.delta then
      log.error(
        "claude.process_response_line(): Received content_block_delta without delta field: " .. log.inspect(data)
      )
      return
    end

    if data.delta.type == "text_delta" and data.delta.text then
      log.debug("claude.process_response_line(): ... Content text delta: " .. log.inspect(data.delta.text))

      if callbacks.on_content then
        callbacks.on_content(data.delta.text)
      end
    elseif data.delta.type == "input_json_delta" and data.delta.partial_json ~= nil then
      log.debug(
        "claude.process_response_line(): ... Content input_json_delta: " .. log.inspect(data.delta.partial_json)
      )
      -- Tool use JSON deltas are not displayed directly
    elseif data.delta.type == "thinking_delta" and data.delta.thinking then
      log.debug("claude.process_response_line(): ... Content thinking delta: " .. log.inspect(data.delta.thinking))
      -- Thinking deltas are not displayed directly
    elseif data.delta.type == "signature_delta" and data.delta.signature then
      log.debug("claude.process_response_line(): ... Content signature delta received")
      -- Signature deltas are not displayed
    else
      log.error(
        "claude.process_response_line(): Received content_block_delta with unknown delta type: "
          .. log.inspect(data.delta.type)
          .. ", delta: "
          .. log.inspect(data.delta)
      )
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
    log.error(
      "claude.process_response_line(): Received unknown event type from Claude API: "
        .. log.inspect(data.type)
        .. ", data: "
        .. log.inspect(data)
    )
  end
end

return M
