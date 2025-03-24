--- Claude provider for Claudius
--- Implements the Claude API integration
local base = require("claudius.provider.base")
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
    keyring_key_name = "api"
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
    "content-type: application/json"
  }
end

-- Get API endpoint
function M.get_endpoint(self)
  return self.endpoint
end

-- Process a response line from Claude API
function M.process_response_line(self, line, callbacks)
  -- First try parsing the line directly as JSON for error responses
  local ok, error_data = pcall(vim.fn.json_decode, line)
  if ok and error_data.type == "error" then
    if callbacks.on_error then
      local msg = "Claude API error"
      if error_data.error and error_data.error.message then
        msg = error_data.error.message
      end
      callbacks.on_error(msg)
    end
    return
  end

  -- Otherwise handle normal event stream format
  if not line:match("^data: ") then
    return
  end

  local json_str = line:gsub("^data: ", "")
  if json_str == "[DONE]" then
    if callbacks.on_done then
      callbacks.on_done()
    end
    return
  end

  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    return
  end

  -- Handle error responses
  if data.type == "error" then
    if callbacks.on_error then
      local msg = "Claude API error"
      if data.error and data.error.message then
        msg = data.error.message
      end
      callbacks.on_error(msg)
    end
    return
  end

  -- Track usage information
  if data.type == "message_start" then
    -- Get input tokens from message.usage in message_start event
    if data.message and data.message.usage and data.message.usage.input_tokens then
      if callbacks.on_usage then
        callbacks.on_usage({
          type = "input",
          tokens = data.message.usage.input_tokens
        })
      end
    end
  end
  
  -- Track output tokens from usage field in any event
  if data.usage and data.usage.output_tokens then
    if callbacks.on_usage then
      callbacks.on_usage({
        type = "output",
        tokens = data.usage.output_tokens
      })
    end
  end

  -- Handle message_stop event
  if data.type == "message_stop" then
    if callbacks.on_message_complete then
      callbacks.on_message_complete()
    end
  end

  -- Handle content blocks
  if data.type == "content_block_delta" and data.delta and data.delta.text then
    if callbacks.on_content then
      callbacks.on_content(data.delta.text)
    end
  end
end

return M
