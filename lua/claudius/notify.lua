--- Claudius notification functionality
local M = {}

local notifications = {}
local ns_id = vim.api.nvim_create_namespace("claudius_notify")

-- Default options
local default_opts = {
  timeout = 5000, -- Time in ms before auto-dismiss
  width = 40,     -- Max width of notification
  padding = 1,    -- Padding around content
  border = "rounded",
  title = nil     -- Optional title for the notification
}

-- Create a notification window
local function create_notification(msg, opts)
  opts = vim.tbl_deep_extend("force", default_opts, opts or {})
  
  -- Split message into lines first
  local msg_lines = vim.split(msg, "\n", { plain = true })
  local lines = {}
  
  -- Process each line separately for wrapping
  for _, msg_line in ipairs(msg_lines) do
    if msg_line == "" then
      table.insert(lines, "")
    else
      local current_line = ""
      for word in msg_line:gmatch("%S+") do
        if #current_line + #word + 1 <= opts.width then
          current_line = current_line == "" and word or current_line .. " " .. word
        else
          table.insert(lines, current_line)
          current_line = word
        end
      end
      if current_line ~= "" then
        table.insert(lines, current_line)
      end
    end
  end

  -- Calculate dimensions
  local width = math.min(opts.width, vim.o.columns - 4)
  local height = #lines
  
  -- Position in top-right corner
  local row = 1
  local col = vim.o.columns - width - 2

  -- Adjust position based on existing notifications
  for _, notif in ipairs(notifications) do
    if notif.valid then
      row = row + notif.height + 1
    end
  end

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")

  -- Create window with title if provided
  local win_opts = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.border,
    noautocmd = true
  }
  
  if opts.title then
    win_opts.title = opts.title
    win_opts.title_pos = "center"
  end
  
  local win_id = vim.api.nvim_open_win(bufnr, false, win_opts)

  -- Set window options
  vim.api.nvim_win_set_option(win_id, "wrap", true)
  vim.api.nvim_win_set_option(win_id, "winblend", 15)

  -- Create notification object first
  local notification = {
    win_id = win_id,
    bufnr = bufnr,
    height = height,
    dismissed = false,
    timer = nil -- Will be set after object creation
  }
  
  -- Now set up the timer with access to the notification object
  notification.timer = vim.fn.timer_start(opts.timeout, function()
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
    -- Find and remove this notification from the list
    for i, n in ipairs(notifications) do
      if n == notification then
        table.remove(notifications, i)
        break
      end
    end
    notification.dismissed = true
  end)
  
  table.insert(notifications, notification)
  
  -- Clean up old notifications
  notifications = vim.tbl_filter(function(n)
    return not n.dismissed
  end, notifications)

  return notification
end

-- Show a notification
function M.show(msg, opts)
  vim.schedule(function()
    create_notification(msg, opts)
  end)
end

return M
