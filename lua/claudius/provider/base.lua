--- Base provider for Claudius
--- Defines the interface that all providers must implement
local log = require("claudius.logging")
local M = {}

-- Provider constructor
function M.new(opts)
  local provider = setmetatable({
    parameters = opts or {}, -- parameters now includes the model
    state = {
      api_key = nil,
    },
  }, { __index = M })

  return provider
end

-- Initialize the provider
function M.init(self)
  -- To be implemented by specific providers
end

-- Try to get API key from system keyring (local helper function)
local function try_keyring(service_name, key_name, project_id)
  if vim.fn.has("linux") == 1 then
    local cmd
    if project_id then
      -- Include project_id in the lookup if provided
      cmd = string.format(
        "secret-tool lookup service %s key %s project_id %s 2>/dev/null",
        service_name,
        key_name,
        project_id
      )
    else
      cmd = string.format("secret-tool lookup service %s key %s 2>/dev/null", service_name, key_name)
    end

    local handle = io.popen(cmd)
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
function M.get_api_key(self, opts)
  -- Return cached key if we have it and it's not empty
  if self.state.api_key and self.state.api_key ~= "" then
    log.debug("get_api_key(): Using cached API key")
    return self.state.api_key
  end

  -- Reset the API key to nil to ensure we don't use an empty string
  self.state.api_key = nil

  -- Try environment variable if provided
  if opts and opts.env_var_name then
    local env_key = os.getenv(opts.env_var_name)
    -- Only set if not empty
    if env_key and env_key ~= "" then
      self.state.api_key = env_key
    end
  end

  -- Try system keyring if no env var and service/key names are provided
  if not self.state.api_key and opts and opts.keyring_service_name and opts.keyring_key_name then
    -- First try with project_id if provided
    if opts.keyring_project_id then
      local key = try_keyring(opts.keyring_service_name, opts.keyring_key_name, opts.keyring_project_id)
      if key and key ~= "" then
        self.state.api_key = key
        log.debug(
          "get_api_key(): Retrieved API key from keyring with project ID: " .. log.inspect(opts.keyring_project_id)
        )
      end
    end

    -- Fall back to generic lookup if project-specific key wasn't found
    if not self.state.api_key then
      local key = try_keyring(opts.keyring_service_name, opts.keyring_key_name)
      if key and key ~= "" then
        self.state.api_key = key
      end
    end
  end

  return self.state.api_key
end

-- Format messages for API (to be implemented by specific providers)
function M.format_messages(self, messages, system_message)
  -- To be implemented by specific providers
end

-- Create request body (to be implemented by specific providers)
function M.create_request_body(self, formatted_messages, system_message)
  -- To be implemented by specific providers
end

-- Get request headers (to be implemented by specific providers)
function M.get_request_headers(self)
  -- To be implemented by specific providers
end

-- Get API endpoint (to be implemented by specific providers)
function M.get_endpoint(self)
  -- To be implemented by specific providers
end

-- Create temporary file for request body (local helper function)
local function create_temp_file(request_body)
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
    return nil, "Failed to create temporary file"
  end

  f:write(vim.fn.json_encode(request_body))
  f:close()

  return tmp_file
end

-- Redact sensitive information from headers
local function redact_sensitive_header(header)
  -- Check if header contains sensitive information (API keys, tokens)
  if header:match("^Authorization:") or header:lower():match("%-key:") or header:lower():match("key:") then
    -- Extract the header name
    local header_name = header:match("^([^:]+):")
    if header_name then
      return header_name .. ": REDACTED"
    end
  end
  return header
end

-- Escape shell arguments properly
local function escape_shell_arg(arg)
  -- Basic shell escaping for arguments
  if arg:match("[%s'\"]") then
    -- If it contains spaces, quotes, etc., wrap in double quotes and escape internal double quotes
    return '"' .. arg:gsub('"', '\\"') .. '"'
  end
  return arg
end

-- Format curl command for logging
local function format_curl_command_for_log(cmd)
  local result = {}
  for i, arg in ipairs(cmd) do
    if i > 1 and cmd[i - 1] == "-H" then
      -- This is a header, redact sensitive information
      table.insert(result, escape_shell_arg(redact_sensitive_header(arg)))
    else
      -- Regular argument
      table.insert(result, escape_shell_arg(arg))
    end
  end
  return table.concat(result, " ")
end

-- Prepare curl command with common options
function M.prepare_curl_command(self, tmp_file, headers, endpoint)
  local cmd = {
    "curl",
    "-N", -- disable buffering
    "-s", -- silent mode
    "--connect-timeout", "10", -- connection timeout
    "--max-time", "120", -- maximum time allowed
    "--retry", "0", -- disable retries
    "--http1.1", -- force HTTP/1.1 for better interrupt handling
    "-H", "Connection: close", -- request connection close
  }

  -- Add headers
  for _, header in ipairs(headers) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  -- Add request body
  table.insert(cmd, "-d")
  table.insert(cmd, "@" .. tmp_file)

  -- Add endpoint
  table.insert(cmd, endpoint)

  return cmd
end

-- Send request to API using curl
function M.send_request(self, request_body, callbacks)
  -- Reset provider state before sending a new request
  self:reset()

  -- Get API key
  local api_key = self:get_api_key()
  if not api_key then
    if callbacks.on_error then
      callbacks.on_error("No API key available")
    end
    return nil
  end

  -- Create temporary file for request body
  local tmp_file, err = create_temp_file(request_body)
  if not tmp_file then
    if callbacks.on_error then
      callbacks.on_error(err or "Failed to create temporary file")
    end
    return nil
  end

  -- Get headers and endpoint
  local headers = self:get_request_headers()
  local endpoint = self:get_endpoint()

  -- Prepare curl command
  local cmd = self:prepare_curl_command(tmp_file, headers, endpoint)

  -- Log the API request details
  log.debug("send_request(): Sending request to endpoint: " .. endpoint)
  local curl_cmd_log = format_curl_command_for_log(cmd)
  -- Replace the temporary file path with @request.json for easier reproduction
  curl_cmd_log = curl_cmd_log:gsub(vim.fn.escape(tmp_file, "%-%."), "request.json")
  log.debug("send_request(): ... $ " .. curl_cmd_log)
  log.debug("send_request(): ... @request.json <<< " .. vim.fn.json_encode(request_body))

  -- Start job
  local job_id = vim.fn.jobstart(cmd, {
    detach = true, -- Put process in its own group
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            -- Log the raw response line
            log.debug("send_request(): on_stdout: " .. line)

            if callbacks.on_data then
              callbacks.on_data(line) -- Pass raw line to on_data callback
            end

            -- Process the response line (without duplicate logging)
            self:process_response_line(line, callbacks)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            -- Log stderr output
            log.error("send_request(): on_stderr: " .. line)

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

      -- Log exit code
      log.info("send_request(): on_exit: Request completed with exit code: " .. tostring(code))

      -- Check for unprocessed JSON if the provider supports it
      if self.check_unprocessed_json then
        self:check_unprocessed_json(callbacks)
      end

      if callbacks.on_complete then
        callbacks.on_complete(code)
      end
    end,
  })

  return job_id
end

-- Process response line (to be implemented by specific providers)
function M.process_response_line(self, line, callbacks)
  -- To be implemented by specific providers
end

-- Cancel ongoing request
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

-- Delayed process termination
function M.delayed_terminate(self, pid, job_id, delay)
  delay = delay or 500

  vim.defer_fn(function()
    if job_id then
      vim.fn.jobstop(job_id)
      if pid then
        vim.fn.system("kill -KILL " .. pid)
      end
    end
  end, delay)
end

-- Reset provider state before a new request
-- This can be overridden by specific providers to reset their state
function M.reset(self)
  -- Base implementation does nothing by default
  -- Providers can override this to reset their specific state
end

return M
