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

  -- Level 3 folds: ```lua ... ```
  if line:match("^```lua$") then
    return ">3" -- Starts a level 3 fold
  elseif line:match("^```$") then
    -- This assumes ``` closes a ```lua block if a level 3 fold is open.
    return "<3" -- Ends a level 3 fold
  end

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
  -- A level 1 fold (message) ends if the next line starts a new message,
  -- or a thinking block, or a frontmatter block, or if it's the last line.
  if next_line_num <= last_buf_line then
    local next_line_content = vim.fn.getline(next_line_num)
    if next_line_content:match("^@[%w]+:") or -- Next line is a new message
       next_line_content:match("^<thinking>$") or -- Next line is a thinking block
       next_line_content:match("^```lua$") then -- Next line is a frontmatter block
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

  -- Check for frontmatter fold (level 3)
  if line_content:match("^```lua$") then
    return string.format("```lua ... ``` (%d lines)", lines_count)
  end

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
