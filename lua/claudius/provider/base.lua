--- Base provider for Claudius
--- Defines the interface that all providers must implement
local M = {}

-- Provider constructor
function M.new(opts)
  local provider = setmetatable({
    options = opts or {},
    state = {
      api_key = nil,
    }
  }, { __index = M })
  
  return provider
end

-- Initialize the provider
function M.init(self)
  -- To be implemented by specific providers
end

-- Get API key (to be implemented by specific providers)
function M.get_api_key(self)
  -- To be implemented by specific providers
end

-- Format messages for API (to be implemented by specific providers)
function M.format_messages(self, messages, system_message)
  -- To be implemented by specific providers
end

-- Create request body (to be implemented by specific providers)
function M.create_request_body(self, formatted_messages, system_message, opts)
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

-- Create temporary file for request body
function M.create_temp_file(self, request_body)
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
  -- Get API key
  local api_key = self:get_api_key()
  if not api_key then
    if callbacks.on_error then
      callbacks.on_error("No API key available")
    end
    return nil
  end
  
  -- Create temporary file for request body
  local tmp_file, err = self:create_temp_file(request_body)
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

return M
