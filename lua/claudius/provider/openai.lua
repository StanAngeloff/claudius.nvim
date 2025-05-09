--- OpenAI provider for Claudius
--- Implements the OpenAI API integration
local base = require("claudius.provider.base")
local log = require("claudius.logging")
local M = {}

-- Create a new OpenAI provider instance
function M.new(merged_config)
  local provider = base.new(merged_config) -- Pass the already merged config to base

  -- OpenAI-specific state (endpoint, version)
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
function M.create_request_body(self, formatted_messages, _)
  -- Access parameters directly from self.parameters
  local max_tokens = self.parameters.max_tokens
  local temperature = self.parameters.temperature

  local request_body = {
    model = self.parameters.model, -- Model is already directly in self.parameters
    messages = formatted_messages,
    max_tokens = max_tokens,
    temperature = temperature,
    stream = true,
    stream_options = {
      include_usage = true, -- Request usage information in the final chunk
    },
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
    log.debug("openai.process_response_line(): Received [DONE] message")

    if callbacks.on_done then
      callbacks.on_done()
    end
    return
  end

  -- Handle final chunk with usage information (empty choices array with usage data)
  if line:match("^data: ") then
    local json_str = line:gsub("^data: ", "")
    local ok, data = pcall(vim.fn.json_decode, json_str)

    if ok and data and data.choices and #data.choices == 0 and data.usage then
      log.debug(
        "openai.process_response_line(): Received final chunk with usage information: " .. log.inspect(data.usage)
      )

      -- Process usage information
      if type(data.usage) == "table" then
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

        -- Signal message completion (this is the only place we should call it)
        if callbacks.on_message_complete then
          callbacks.on_message_complete()
        end
      end
      return
    end
  end

  -- Check for expected format: lines should start with "data: "
  if not line:match("^data: ") then
    -- This is not a standard SSE data line or potentially a non-SSE JSON error
    log.debug("openai.process_response_line(): Received non-SSE line: " .. line)

    -- Try parsing as a direct JSON error response
    local ok, error_data = pcall(vim.fn.json_decode, line)
    if ok and error_data.error then
      local msg = "OpenAI API error"
      if error_data.error and error_data.error.message then
        msg = error_data.error.message
      end

      -- Log the error
      log.error("openai.process_response_line(): OpenAI API error (parsed from non-SSE line): " .. log.inspect(msg))

      if callbacks.on_error then
        callbacks.on_error(msg) -- Keep original message for user notification
      end
      return
    end

    -- If we can't parse it as an error, log and ignore
    log.error("openai.process_response_line(): Ignoring unrecognized response line: " .. line)
    return
  end

  -- Extract JSON from data: prefix
  local json_str = line:gsub("^data: ", "")
  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    log.error("openai.process_response_line(): Failed to parse JSON from response: " .. json_str)
    return
  end

  -- Validate the response structure
  if type(data) ~= "table" then
    log.error(
      "openai.process_response_line(): Expected table in response, got type: "
        .. type(data)
        .. ", data: "
        .. log.inspect(data)
    )
    return
  end

  -- Handle error responses
  if data.error then
    local msg = "OpenAI API error"
    if data.error and data.error.message then
      msg = data.error.message
    end

    log.error("openai.process_response_line(): OpenAI API error in response data: " .. log.inspect(msg))

    if callbacks.on_error then
      callbacks.on_error(msg) -- Keep original message for user notification
    end
    return
  end

  -- Note: Usage information is now handled in the final chunk with empty choices array

  -- Handle content deltas
  if not data.choices then
    log.error(
      "openai.process_response_line(): Expected 'choices' in response data, but not found: " .. log.inspect(data)
    )
    return
  end

  if not data.choices[1] then
    log.error(
      "openai.process_response_line(): Expected at least one choice in response, but none found: " .. log.inspect(data)
    )
    return
  end

  if not data.choices[1].delta then
    log.error(
      "openai.process_response_line(): Expected 'delta' in first choice, but not found: "
        .. log.inspect(data.choices[1])
    )
    return
  end

  local delta = data.choices[1].delta

  -- Check if this is the role marker without content
  if delta.role == "assistant" and not delta.content then
    -- This is just the role marker, skip it
    log.debug("openai.process_response_line(): Received assistant role marker, skipping")
    return
  end

  -- Handle actual content
  if delta.content then
    log.debug("openai.process_response_line(): Content delta: " .. log.inspect(delta.content))

    if callbacks.on_content then
      callbacks.on_content(delta.content)
    end
  end

  -- Check if this is the finish_reason (only if it has a meaningful value, not null)
  if
    data.choices[1].finish_reason
    and data.choices[1].finish_reason ~= vim.NIL
    and data.choices[1].finish_reason ~= nil
  then
    log.debug("openai.process_response_line(): Received finish_reason: " .. log.inspect(data.choices[1].finish_reason))
    -- We'll let the final chunk with usage information trigger on_message_complete
  end
end

return M
