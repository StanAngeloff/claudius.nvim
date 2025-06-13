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
function M.format_messages(self, messages)
  local formatted = {}
  local system_message = nil

  -- Look for system message in the messages
  for _, msg in ipairs(messages) do
    if msg.type == "System" then
      system_message = msg.content:gsub("%s+$", "")
      break -- Assuming only one system message is relevant
    end
  end

  -- Add system message if found
  if system_message then
    table.insert(formatted, {
      role = "system",
      content = system_message,
    })
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
        content = msg.content:gsub("%s+$", ""), -- Content is passed through directly
      })
    end
  end

  return formatted, system_message -- Return formatted messages and the extracted system message
end

-- Create request body for OpenAI API
function M.create_request_body(self, formatted_messages, _)
  local api_messages = {}
  for _, msg in ipairs(formatted_messages) do
    if msg.role == "user" then
      local content_parts_for_api = {} -- Holds {type="text", text=...} or other part types
      local has_multimedia_part = false -- Flag if content must be an array (e.g., for images, PDFs)

      local content_parser_coro = self:parse_message_content_chunks(msg.content)
      while true do
        local status, chunk = coroutine.resume(content_parser_coro)
        if not status or not chunk then -- Coroutine finished or errored
          break
        end

        if chunk.type == "text" then
          if chunk.value and #chunk.value > 0 then
            table.insert(content_parts_for_api, { type = "text", text = chunk.value })
          end
        elseif chunk.type == "file" then
          if chunk.readable and chunk.content and chunk.mime_type then
            local encoded_data
            if
              chunk.mime_type == "image/jpeg"
              or chunk.mime_type == "image/png"
              or chunk.mime_type == "image/webp"
              or chunk.mime_type == "image/gif"
            then
              encoded_data = vim.base64.encode(chunk.content)
              table.insert(content_parts_for_api, {
                type = "image_url",
                image_url = {
                  url = "data:" .. chunk.mime_type .. ";base64," .. encoded_data,
                  detail = "auto", -- Or "low", "high" as per OpenAI docs
                },
              })
              has_multimedia_part = true
              log.debug(
                'openai.create_request_body: Added image_url part for "'
                  .. chunk.filename
                  .. '" (MIME: '
                  .. chunk.mime_type
                  .. ")"
              )
            elseif chunk.mime_type == "application/pdf" then
              encoded_data = vim.base64.encode(chunk.content)
              table.insert(content_parts_for_api, {
                type = "file",
                file = {
                  filename = chunk.filename, -- The actual filename
                  file_data = "data:application/pdf;base64," .. encoded_data,
                },
              })
              has_multimedia_part = true
              log.debug(
                'openai.create_request_body: Added file part for PDF "'
                  .. chunk.filename
                  .. '" (MIME: '
                  .. chunk.mime_type
                  .. ")"
              )
            elseif chunk.mime_type:sub(1, 5) == "text/" then
              table.insert(content_parts_for_api, { type = "text", text = chunk.content })
              log.debug(
                'openai.create_request_body: Added text part for "'
                  .. chunk.filename
                  .. '" (MIME: '
                  .. chunk.mime_type
                  .. ")"
              )
            else
              vim.notify(
                "Claudius (OpenAI): @file reference with MIME type '"
                  .. chunk.mime_type
                  .. "' is not supported for direct inclusion. The reference will be sent as text.",
                vim.log.levels.WARN,
                { title = "Claudius Notification" }
              )
              table.insert(content_parts_for_api, { type = "text", text = "@" .. chunk.raw_filename })
            end
          else
            log.warn(
              'openai.create_request_body: @file reference "'
                .. chunk.raw_filename
                .. '" (cleaned: "'
                .. chunk.filename
                .. '") not readable or missing data. Error: '
                .. (chunk.error or "unknown")
                .. ". Inserting raw text."
            )
            table.insert(content_parts_for_api, { type = "text", text = "@" .. chunk.raw_filename })
          end
        end
      end

      local final_api_content
      if #content_parts_for_api == 0 then
        final_api_content = msg.content:gsub("%s+$", "") -- Original trimmed string if no parts generated
      elseif has_multimedia_part then
        final_api_content = content_parts_for_api -- Array of parts if multimedia content is present
      else
        -- Concatenate all text parts into a single string if only text parts exist
        local text_only_accumulator = {}
        for _, part in ipairs(content_parts_for_api) do
          if part.type == "text" and part.text then
            table.insert(text_only_accumulator, part.text)
          end
        end
        final_api_content = table.concat(text_only_accumulator)
      end

      table.insert(api_messages, {
        role = msg.role,
        content = final_api_content,
      })
    else -- Assistant or System messages
      table.insert(api_messages, {
        role = msg.role,
        content = msg.content, -- Already trimmed by format_messages
      })
    end
  end

  local request_body = {
    model = self.parameters.model,
    messages = api_messages,
    -- max_tokens or max_completion_tokens will be set conditionally below
    temperature = self.parameters.temperature,
    stream = true,
    stream_options = {
      include_usage = true, -- Request usage information in the final chunk
    },
  }

  -- Conditionally set max_tokens or max_completion_tokens and add reasoning_effort
  if self.parameters.reasoning and self.parameters.reasoning ~= "" then
    request_body.max_completion_tokens = self.parameters.max_tokens
    request_body.reasoning_effort = self.parameters.reasoning -- Add reasoning_effort
    log.debug(
      "openai.create_request_body: Using max_completion_tokens: "
        .. tostring(self.parameters.max_tokens)
        .. " and reasoning_effort: "
        .. self.parameters.reasoning
    )
  else
    request_body.max_tokens = self.parameters.max_tokens
    log.debug("openai.create_request_body: Using max_tokens: " .. tostring(self.parameters.max_tokens))
  end

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

  -- Handle [DONE] message
  if json_str == "[DONE]" then
    log.debug("openai.process_response_line(): Received [DONE] message")

    if callbacks.on_done then
      callbacks.on_done()
    end
    return
  end

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
