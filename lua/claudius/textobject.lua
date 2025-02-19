local M = {}

-- Get the bounds of the current message
local function get_message_bounds()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Find start of current message
  local start_line = cur_line
  while start_line > 0 and not lines[start_line]:match("^@[%w]+:") do
    start_line = start_line - 1
  end

  -- If we didn't find a message start, return nil
  if start_line == 0 and not lines[1]:match("^@[%w]+:") then
    return nil
  end

  -- Find end of message
  local end_line = cur_line
  while end_line < #lines do
    end_line = end_line + 1
    if lines[end_line] and lines[end_line]:match("^@[%w]+:") then
      end_line = end_line - 1
      break
    end
  end

  -- Trim trailing empty lines for inner selection
  local inner_end = end_line
  while inner_end > start_line and (not lines[inner_end] or lines[inner_end] == "") do
    inner_end = inner_end - 1
  end

  -- Get the prefix length for the start line
  local prefix_end = lines[start_line]:find(":%s*") + 1
  while lines[start_line]:sub(prefix_end, prefix_end) == " " do
    prefix_end = prefix_end + 1
  end

  return {
    start_line = start_line,
    end_line = end_line,
    inner_end = inner_end,
    prefix_end = prefix_end - 1,
  }
end

-- Text object implementations
function M.message_textobj(type)
  local bounds = get_message_bounds()
  if not bounds then
    return
  end

  local start_pos, end_pos

  if type == 'i' then -- inner message
    -- Get the lines for calculating final column
    local lines = vim.api.nvim_buf_get_lines(0, bounds.start_line - 1, bounds.inner_end, false)
    start_pos = { bounds.start_line, bounds.prefix_end }
    end_pos = { bounds.inner_end, #lines[#lines] }
  else -- around message
    local lines = vim.api.nvim_buf_get_lines(0, bounds.end_line - 1, bounds.end_line, false)
    start_pos = { bounds.start_line, 0 }
    end_pos = { bounds.end_line, #lines[1] }
  end

  -- Set marks for the text object
  vim.api.nvim_buf_set_mark(0, '[', start_pos[1], start_pos[2], {})
  vim.api.nvim_buf_set_mark(0, ']', end_pos[1], end_pos[2], {})
end

-- Setup function to create the text objects
function M.setup()
  -- Create text objects for inner message (im) and around message (am)
  vim.keymap.set('x', 'im', ':<C-u>lua require("claudius.textobject").message_textobj("i")<CR>', 
    { silent = true, buffer = true })
  vim.keymap.set('o', 'im', ':<C-u>lua require("claudius.textobject").message_textobj("i")<CR>', 
    { silent = true, buffer = true })
  vim.keymap.set('x', 'am', ':<C-u>lua require("claudius.textobject").message_textobj("a")<CR>', 
    { silent = true, buffer = true })
  vim.keymap.set('o', 'am', ':<C-u>lua require("claudius.textobject").message_textobj("a")<CR>', 
    { silent = true, buffer = true })
end

return M
