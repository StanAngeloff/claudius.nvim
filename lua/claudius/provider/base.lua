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

-- Send request to API (to be implemented by specific providers)
function M.send_request(self, request_body, callbacks)
  -- To be implemented by specific providers
end

-- Cancel ongoing request (to be implemented by specific providers)
function M.cancel_request(self, request_id)
  -- To be implemented by specific providers
end

-- Process response line (to be implemented by specific providers)
function M.process_response_line(self, line, callbacks)
  -- To be implemented by specific providers
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
