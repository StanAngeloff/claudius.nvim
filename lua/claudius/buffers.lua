--- Buffer state management for Claudius
local M = {}

-- Store buffer-local state
local buffer_state = {}

-- Constants for fold text preview
local MAX_CONTENT_PREVIEW_LINES = 10
local MAX_CONTENT_PREVIEW_LENGTH = 72
local CONTENT_PREVIEW_NEWLINE_CHAR = "⤶"
local CONTENT_PREVIEW_TRUNCATION_MARKER = "..."

-- Helper function to generate content preview for folds
local function get_fold_content_preview(fold_start_lnum, fold_end_lnum)
  local content_lines = {}
  -- Content is between the start and end delimiter lines
  local num_content_lines_in_fold = fold_end_lnum - fold_start_lnum - 1

  if num_content_lines_in_fold <= 0 then
    return "" -- No content lines within the fold
  end

  local lines_to_fetch = math.min(num_content_lines_in_fold, MAX_CONTENT_PREVIEW_LINES)

  for i = 1, lines_to_fetch do
    local current_content_line_num = fold_start_lnum + i
    local line_text = vim.fn.getline(current_content_line_num)
    table.insert(content_lines, vim.fn.trim(line_text)) -- Trim each line
  end

  local preview_str = table.concat(content_lines, CONTENT_PREVIEW_NEWLINE_CHAR)
  preview_str = vim.fn.trim(preview_str) -- Trim the whole concatenated string

  if #preview_str > MAX_CONTENT_PREVIEW_LENGTH then
    -- Ensure we have enough space for the truncation marker
    local truncated_length = MAX_CONTENT_PREVIEW_LENGTH - #CONTENT_PREVIEW_TRUNCATION_MARKER
    if truncated_length < 0 then truncated_length = 0 end -- Handle edge case

    preview_str = preview_str:sub(1, truncated_length)
    preview_str = preview_str .. CONTENT_PREVIEW_TRUNCATION_MARKER
  end

  return preview_str
end

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

  -- Level 3 folds: ```lua ... ``` (only if ```lua is on the first line)
  if lnum == 1 and line:match("^```lua$") then
    return ">3" -- Starts a level 3 fold
  elseif line:match("^```$") then
    -- This assumes ``` closes a ```lua block if a level 3 fold was opened on line 1.
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
    -- A level 1 fold (message) ends if the next line starts a new message (@Role:)
    -- or a thinking block (<thinking>). A ```lua block only ends a message
    -- if it's on the first line of the file, which is handled by the >3 rule.
    if next_line_content:match("^@[%w]+:") or -- Next line is a new message
       next_line_content:match("^<thinking>$") then -- Next line is a thinking block
      return "<1" -- Ends a level 1 fold
    end
  elseif lnum == last_buf_line then -- Current line is the last in buffer
    return "<1" -- Ends a level 1 fold
  end

  -- If none of the above, the line continues the current fold level.
  return "="
end

function M.get_fold_text()
  local foldstart_lnum = vim.v.foldstart
  local foldend_lnum = vim.v.foldend
  local first_line_content = vim.fn.getline(foldstart_lnum)
  local total_fold_lines = foldend_lnum - foldstart_lnum + 1

  -- Check for frontmatter fold (level 3) - only if it started on line 1
  if foldstart_lnum == 1 and first_line_content:match("^```lua$") then
    local preview = get_fold_content_preview(foldstart_lnum, foldend_lnum)
    if preview ~= "" then
      return string.format("```lua %s ``` (%d lines)", preview, total_fold_lines)
    else
      return string.format("```lua (%d lines)", total_fold_lines)
    end
  end

  -- Check if this is a thinking fold (level 2)
  if first_line_content:match("^<thinking>$") then
    local preview = get_fold_content_preview(foldstart_lnum, foldend_lnum)
    if preview ~= "" then
      return string.format("<thinking> %s </thinking> (%d lines)", preview, total_fold_lines)
    else
      return string.format("<thinking> (%d lines)", total_fold_lines)
    end
  end

  -- Existing logic for message folds (level 1)
  -- Note: Using foldstart_lnum, first_line_content, total_fold_lines defined above
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
