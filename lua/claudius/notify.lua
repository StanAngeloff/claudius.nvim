--- Claudius notification functionality
local M = {}

-- Store the last notification
local last_notification = nil
local notifications = {}

-- Default notification options
M.default_opts = {
  enabled = true,
  timeout = 8000,
  max_width = 60,
  padding = 1,
  border = "rounded",
  title = nil,
}

-- Reposition all active notifications
local function reposition_notifications()
  local row = 1
  for _, notif in ipairs(notifications) do
    if notif.valid and vim.api.nvim_win_is_valid(notif.win_id) then
      vim.api.nvim_win_set_config(notif.win_id, {
        relative = "editor",
        row = row,
        col = vim.o.columns - notif.width - 2,
      })
      row = row + notif.height + 1
    end
  end
end

-- Create a notification window
local function create_notification(msg, opts)
  -- Split message into lines and calculate max line length
  local msg_lines = vim.split(msg, "\n", { plain = true })
  local lines = {}
  local max_line_length = 0

  -- Process each line separately for wrapping if needed
  for _, msg_line in ipairs(msg_lines) do
    if msg_line == "" then
      table.insert(lines, "")
    else
      -- If line is longer than max_width, wrap it
      if #msg_line > opts.max_width then
        local current_line = ""
        for word in msg_line:gmatch("%S+") do
          if #current_line + #word + 1 <= opts.max_width then
            current_line = current_line == "" and word or current_line .. " " .. word
          else
            table.insert(lines, current_line)
            max_line_length = math.max(max_line_length, #current_line)
            current_line = word
          end
        end
        if current_line ~= "" then
          table.insert(lines, current_line)
          max_line_length = math.max(max_line_length, #current_line)
        end
      else
        -- Line fits within max_width, keep it as is
        table.insert(lines, msg_line)
        max_line_length = math.max(max_line_length, #msg_line)
      end
    end
  end

  -- Add padding to each line
  local padded_lines = {}
  local padding_str = string.rep(" ", opts.padding)
  for _, line in ipairs(lines) do
    if line:match("%S") then
      table.insert(padded_lines, padding_str .. line .. padding_str)
    else
      table.insert(padded_lines, line) -- Keep empty lines as-is
    end
  end

  -- Calculate dimensions - use actual content width but respect screen bounds
  local width = math.min(max_line_length + (opts.padding * 2), vim.o.columns - 4)
  local height = #padded_lines

  -- Calculate initial position (will be adjusted by reposition)
  local row = 1
  local col = vim.o.columns - width - 2

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, padded_lines)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(bufnr, "filetype", "claudius_notify")

  -- Create window with title if provided
  local win_opts = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.border,
    noautocmd = true,
  }

  if opts.title then
    win_opts.title = opts.title
    win_opts.title_pos = "center"
  end

  local win_id = vim.api.nvim_open_win(bufnr, false, win_opts)

  -- Set window options
  vim.api.nvim_win_set_option(win_id, "wrap", true)
  vim.api.nvim_win_set_option(win_id, "winblend", 15)
  vim.api.nvim_win_set_option(win_id, "conceallevel", 2)
  vim.api.nvim_win_set_option(win_id, "concealcursor", "nc")

  -- Create notification object first
  local notification = {
    win_id = win_id,
    bufnr = bufnr,
    height = height,
    width = width,
    dismissed = false,
    valid = true,
    timer = nil, -- Will be set after object creation
  }

  -- Now set up the timer with access to the notification object
  notification.timer = vim.fn.timer_start(opts.timeout, function()
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
    notification.valid = false
    notification.dismissed = true

    -- Clean up notifications list and reposition remaining ones
    notifications = vim.tbl_filter(function(n)
      return not n.dismissed
    end, notifications)

    reposition_notifications()
  end)

  table.insert(notifications, notification)
  reposition_notifications()

  return notification
end

-- Show a notification if enabled
function M.show(msg, opts)
  -- Merge with default options
  local final_opts = vim.tbl_deep_extend("force", M.default_opts, opts or {})

  -- Check if notifications are enabled
  if not final_opts.enabled then
    return
  end

  -- Store this notification as the last one
  last_notification = {
    message = msg,
    options = final_opts
  }

  vim.schedule(function()
    create_notification(msg, final_opts)
  end)
end

-- Function to recall last notification
function M.recall_last()
  if last_notification then
    M.show(last_notification.message, last_notification.options)
  else
    vim.notify("No previous notification to recall", vim.log.levels.INFO)
  end
end

return M
