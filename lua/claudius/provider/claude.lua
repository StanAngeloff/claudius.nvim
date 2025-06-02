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
function M.format_messages(self, messages)
  local formatted = {}
  local system_message = nil -- System message is handled in create_request_body

  for _, msg in ipairs(messages) do
    local role = msg.type == "You" and "user" or msg.type == "Assistant" and "assistant" or nil

    if role then
      table.insert(formatted, {
        role = role,
        content = msg.content:gsub("%s+$", ""), -- Content is passed through directly
      })
    end
    -- Extract system message if found
    if msg.type == "System" then
      system_message = msg.content:gsub("%s+$", "")
    end
  end

  return formatted, system_message
end

-- Create request body for Claude API
function M.create_request_body(self, formatted_messages, system_message)
  local api_messages = {}
  for _, msg in ipairs(formatted_messages) do
    if msg.role == "user" then
      local content_blocks = {} -- Will hold {type="text", text=...} or {type="image", source=...} etc.
      local content_parser_coro = self:parse_message_content_chunks(msg.content)

      while true do
        local status, chunk = coroutine.resume(content_parser_coro)
        if not status or not chunk then -- Coroutine finished or errored
          break
        end

        if chunk.type == "text" then
          if chunk.value and #chunk.value > 0 then
            table.insert(content_blocks, { type = "text", text = chunk.value })
          end
        elseif chunk.type == "file" then
          if chunk.readable and chunk.content and chunk.mime_type then
            local encoded_data
            if
              chunk.mime_type == "image/jpeg"
              or chunk.mime_type == "image/png"
              or chunk.mime_type == "image/gif"
              or chunk.mime_type == "image/webp"
            then
              encoded_data = vim.base64.encode(chunk.content)
              table.insert(content_blocks, {
                type = "image",
                source = {
                  type = "base64",
                  media_type = chunk.mime_type,
                  data = encoded_data,
                },
              })
              log.debug(
                'claude.create_request_body: Added image part for "'
                  .. chunk.filename
                  .. '" (MIME: '
                  .. chunk.mime_type
                  .. ")"
              )
            elseif chunk.mime_type == "application/pdf" then
              encoded_data = vim.base64.encode(chunk.content)
              table.insert(content_blocks, {
                type = "document",
                source = {
                  type = "base64",
                  media_type = chunk.mime_type, -- API expects "application/pdf"
                  data = encoded_data,
                },
              })
              log.debug(
                'claude.create_request_body: Added document part for "'
                  .. chunk.filename
                  .. '" (MIME: '
                  .. chunk.mime_type
                  .. ")"
              )
            elseif chunk.mime_type:sub(1, 5) == "text/" then
              -- Embed content of text files directly
              table.insert(content_blocks, { type = "text", text = chunk.content })
              log.debug(
                'claude.create_request_body: Added text part for "'
                  .. chunk.filename
                  .. '" (MIME: '
                  .. chunk.mime_type
                  .. ")"
              )
            else
              -- Unsupported MIME type for direct inclusion
              vim.notify(
                "Claudius (Claude): @file reference with MIME type '"
                  .. chunk.mime_type
                  .. "' is not supported for direct inclusion. The reference will be sent as text.",
                vim.log.levels.WARN,
                { title = "Claudius Notification" }
              )
              table.insert(content_blocks, { type = "text", text = "@" .. chunk.raw_filename })
            end
          else
            -- File not readable or missing essential data
            log.warn(
              'claude.create_request_body: @file reference "'
                .. chunk.raw_filename
                .. '" (cleaned: "'
                .. chunk.filename
                .. '") not readable or missing data. Error: '
                .. (chunk.error or "unknown")
                .. ". Inserting raw text."
            )
            table.insert(content_blocks, { type = "text", text = "@" .. chunk.raw_filename })
          end
        end
      end

      local final_user_content
      if #content_blocks > 0 then
        final_user_content = content_blocks
      else
        -- Original content was empty/whitespace, or resulted in no processable blocks.
        -- Use the original string content, trimmed, as per Claude API (string | object[]).
        final_user_content = msg.content:gsub("%s+$", "")
        log.debug(
          "claude.create_request_body: User content resulted in empty 'content_blocks'. Using original string content: \""
            .. final_user_content
            .. '"'
        )
      end
      table.insert(api_messages, {
        role = msg.role,
        content = final_user_content,
      })
    elseif msg.role == "assistant" then -- Assistant messages in the request history
      -- Assistant message content should also be in the new block structure.
      -- Assuming assistant messages are always text.
      table.insert(api_messages, {
        role = msg.role,
        content = { { type = "text", text = msg.content } }, -- Already trimmed by format_messages
      })
    end
  end

  local request_body = {
    model = self.parameters.model,
    messages = api_messages,
    system = system_message,
    max_tokens = self.parameters.max_tokens,
    temperature = self.parameters.temperature,
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
