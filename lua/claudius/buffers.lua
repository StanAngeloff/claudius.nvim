--- Buffer state management for Claudius
local M = {}

-- Store buffer-local state
local buffer_state = {}

-- Initialize state for a buffer
function M.init_buffer(bufnr)
  buffer_state[bufnr] = {
    current_request = nil,
    request_cancelled = false,
    spinner_timer = nil,
    current_usage = {
      input_tokens = 0,
      output_tokens = 0,
    },
  }
end

-- Clean up state when buffer is deleted
function M.cleanup_buffer(bufnr)
  if buffer_state[bufnr] then
    -- Cancel any ongoing request
    if buffer_state[bufnr].current_request then
      local job_id = buffer_state[bufnr].current_request
      vim.fn.jobstop(job_id)
    end
    -- Stop any running timer
    if buffer_state[bufnr].spinner_timer then
      vim.fn.timer_stop(buffer_state[bufnr].spinner_timer)
    end
    buffer_state[bufnr] = nil
  end
end

-- Get state for a buffer
function M.get_state(bufnr)
  if not buffer_state[bufnr] then
    M.init_buffer(bufnr)
  end
  return buffer_state[bufnr]
end

-- Set specific state value for a buffer
function M.set_state(bufnr, key, value)
  if not buffer_state[bufnr] then
    M.init_buffer(bufnr)
  end
  buffer_state[bufnr][key] = value
end

return M
