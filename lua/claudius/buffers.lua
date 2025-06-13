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

-- Folding functions
function M.get_fold_level(lnum)
  local line = vim.fn.getline(lnum)
  local next_line_num = lnum + 1
  local last_buf_line = vim.fn.line("$")

  -- Level 2 folds: <thinking>...</thinking>
  if line:match("^<thinking>$") then
    return ">2" -- Starts a level 2 fold
  elseif line:match("^</thinking>$") then
    return "<2" -- Ends a level 2 fold
  end

  -- Level 1 folds: @Role:...
  if line:match("^@[%w]+:") then
    return ">1" -- Starts a level 1 fold
  end

  -- Check for end of level 1 fold:
  -- This line is the last line of a message if:
  -- 1. The next line starts a new message (@Role:)
  -- 2. This is the last line of the file.
  if next_line_num <= last_buf_line then
    local next_line_content = vim.fn.getline(next_line_num)
    if next_line_content:match("^@[%w]+:") then
      return "<1" -- Ends a level 1 fold
    end
  elseif lnum == last_buf_line then -- Current line is the last in buffer
    return "<1" -- Ends a level 1 fold
  end

  -- If none of the above, the line continues the current fold level.
  return "="
end

function M.get_fold_text()
  local foldstart = vim.v.foldstart
  local line_content = vim.fn.getline(foldstart)
  local lines_count = vim.v.foldend - vim.v.foldstart + 1

  -- Check if this is a thinking fold (level 2)
  if line_content:match("^<thinking>$") then
    return string.format("<thinking>...</thinking> (%d lines)", lines_count)
  end

  -- Existing logic for message folds (level 1)
  local role_type = line_content:match("^(@[%w]+:)")
  if not role_type then
    -- This case should ideally not be reached if get_fold_level is correct
    -- and we are processing a valid fold start.
    return line_content
  end

  -- Get the first line of content (excluding the role type)
  local content = line_content:sub(#role_type + 1):gsub("^%s*", "")

  -- Create fold text: role type + first line + number of lines
  return string.format("%s %s... (%d lines)", role_type, content:sub(1, 50), lines_count)
end

return M
