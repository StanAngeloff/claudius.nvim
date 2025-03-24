--- OpenAI provider for Claudius
--- Implements the OpenAI API integration
local base = require("claudius.provider.base")
local M = {}

-- Create a new OpenAI provider instance
function M.new(opts)
  local provider = base.new(opts)

  -- OpenAI-specific state
  provider.endpoint = "https://api.openai.com/v1/chat/completions"
  provider.api_version = "2023-05-15" -- OpenAI API version

  -- Set metatable to use OpenAI methods
  return setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
end

-- Get API key from environment, keyring, or prompt
function M.get_api_key(self)
  -- Call the base implementation with OpenAI-specific parameters
  return require("claudius.provider.base").get_api_key(self, {
    env_var_name = "OPENAI_API_KEY",
    keyring_service_name = "openai",
    keyring_key_name = "api",
  })
end

-- Format messages for OpenAI API
function M.format_messages(self, messages, system_message)
  local formatted = {}
  
  -- Add system message if provided
  if system_message then
    table.insert(formatted, {
      role = "system",
      content = system_message,
    })
  else
    -- Look for system message in the messages
    for _, msg in ipairs(messages) do
      if msg.type == "System" then
        table.insert(formatted, {
          role = "system",
          content = msg.content:gsub("%s+$", ""),
        })
        break
      end
    end
  end

  -- Add user and assistant messages
  for _, msg in ipairs(messages) do
    local role = nil
    if msg.type == "You" then
      role = "user"
    elseif msg.type == "Assistant" then
      role = "assistant"
    end

    if role and role ~= "system" then -- Skip system messages as we've handled them
      table.insert(formatted, {
        role = role,
        content = msg.content:gsub("%s+$", ""),
      })
    end
  end

  return formatted, nil -- OpenAI doesn't need a separate system message
end

-- Create request body for OpenAI API
function M.create_request_body(self, formatted_messages, _, opts)
  local request_body = {
    model = opts.model or self.options.model,
    messages = formatted_messages,
    max_tokens = opts.max_tokens or self.options.parameters.max_tokens,
    temperature = opts.temperature or self.options.parameters.temperature,
    stream = true,
  }

  return request_body
end

-- Get request headers for OpenAI API
function M.get_request_headers(self)
  local api_key = self:get_api_key()
  return {
    "Authorization: Bearer " .. api_key,
    "Content-Type: application/json",
  }
end

-- Get API endpoint
function M.get_endpoint(self)
  return self.endpoint
end

-- Process a response line from OpenAI API
function M.process_response_line(self, line, callbacks)
  -- Skip empty lines
  if not line or line == "" then
    return
  end

  -- Handle [DONE] message
  if line == "data: [DONE]" then
    if callbacks.on_done then
      callbacks.on_done()
    end
    return
  end

  -- First try parsing the line directly as JSON for error responses
  if not line:match("^data: ") then
    local ok, error_data = pcall(vim.fn.json_decode, line)
    if ok and error_data.error then
      if callbacks.on_error then
        local msg = "OpenAI API error"
        if error_data.error and error_data.error.message then
          msg = error_data.error.message
        end
        callbacks.on_error(msg)
      end
      return
    end
    return
  end

  -- Handle normal data events
  local json_str = line:gsub("^data: ", "")
  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    return
  end

  -- Handle error responses
  if data.error then
    if callbacks.on_error then
      local msg = "OpenAI API error"
      if data.error and data.error.message then
        msg = data.error.message
      end
      callbacks.on_error(msg)
    end
    return
  end

  -- Track usage information if available
  if data.usage then
    if callbacks.on_usage and data.usage.prompt_tokens then
      callbacks.on_usage({
        type = "input",
        tokens = data.usage.prompt_tokens,
      })
    end
    if callbacks.on_usage and data.usage.completion_tokens then
      callbacks.on_usage({
        type = "output",
        tokens = data.usage.completion_tokens,
      })
    end
  end

  -- Handle content deltas
  if data.choices and data.choices[1] and data.choices[1].delta then
    local delta = data.choices[1].delta
    
    -- Check if this is the end of the message
    if delta.role == "assistant" and not delta.content then
      -- This is just the role marker, skip it
      return
    end
    
    -- Handle actual content
    if delta.content then
      if callbacks.on_content then
        callbacks.on_content(delta.content)
      end
    end
    
    -- Check if this is the finish_reason
    if data.choices[1].finish_reason then
      if callbacks.on_message_complete then
        callbacks.on_message_complete()
      end
    end
  end
end

return M
