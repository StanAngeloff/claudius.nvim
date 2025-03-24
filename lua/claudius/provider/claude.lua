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

-- Try to get API key from system keyring
function M.try_keyring(self)
  if vim.fn.has("linux") == 1 then
    local handle = io.popen("secret-tool lookup service anthropic key api 2>/dev/null")
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result and #result > 0 then
        return result:gsub("%s+$", "") -- Trim whitespace
      end
    end
  end
  return nil
end

-- Get API key from environment, keyring, or prompt
function M.get_api_key(self)
  -- Return cached key if we have it
  if self.state.api_key then
    return self.state.api_key
  end
  
  -- Try environment variable first
  self.state.api_key = os.getenv("ANTHROPIC_API_KEY")
  
  -- Try system keyring if no env var
  if not self.state.api_key then
    self.state.api_key = self:try_keyring()
  end
  
  return self.state.api_key
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

-- Send request to Claude API
function M.send_request(self, request_body, callbacks)
  local api_key = self:get_api_key()
  if not api_key then
    if callbacks.on_error then
      callbacks.on_error("No API key available")
    end
    return nil
  end
  
  -- Create temporary file for request body
  local tmp_file = os.tmpname()
  -- Handle both Unix and Windows paths
  local tmp_dir = tmp_file:match("^(.+)[/\\]")
  local tmp_name = tmp_file:match("[/\\]([^/\\]+)$")
  -- Use the same separator that was in the original path
  local sep = tmp_file:match("[/\\]")
  tmp_file = tmp_dir .. sep .. "claudius_" .. tmp_name
  
  local f = io.open(tmp_file, "w")
  if not f then
    if callbacks.on_error then
      callbacks.on_error("Failed to create temporary file")
    end
    return nil
  end
  f:write(vim.fn.json_encode(request_body))
  f:close()

  -- Prepare curl command
  local cmd = {
    "curl",
    "-N", -- disable buffering
    "-s", -- silent mode
    "--connect-timeout", "10", -- connection timeout
    "--max-time", "120", -- maximum time allowed
    "--retry", "0", -- disable retries
    "--http1.1", -- force HTTP/1.1 for better interrupt handling
    "-H", "Connection: close", -- request connection close
    "-H", "x-api-key: " .. api_key,
    "-H", "anthropic-version: " .. self.api_version,
    "-H", "content-type: application/json",
    "-d", "@" .. tmp_file,
    self.endpoint,
  }

  -- Start job
  local job_id = vim.fn.jobstart(cmd, {
    detach = true, -- Put process in its own group
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            if callbacks.on_data then
              self:process_response_line(line, callbacks)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            if callbacks.on_stderr then
              callbacks.on_stderr(line)
            end
          end
        end
      end
    end,
    on_exit = function(_, code)
      -- Clean up temporary file
      os.remove(tmp_file)
      
      if callbacks.on_complete then
        callbacks.on_complete(code)
      end
    end,
  })
  
  return job_id
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

-- Cancel an ongoing request
function M.cancel_request(self, job_id)
  if not job_id then
    return false
  end
  
  -- Get the process ID
  local pid = vim.fn.jobpid(job_id)
  
  -- Send SIGINT first for clean connection termination
  if pid then
    vim.fn.system("kill -INT " .. pid)
    
    -- Give curl a moment to cleanup, then force kill if still running
    self:delayed_terminate(pid, job_id)
  else
    -- Fallback to jobstop if we couldn't get PID
    vim.fn.jobstop(job_id)
  end
  
  return true
end

return M
