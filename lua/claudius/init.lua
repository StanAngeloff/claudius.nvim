local M = {}
local ns_id = vim.api.nvim_create_namespace("claudius")
local api_key = nil

-- Setup logging
local log_path = vim.fn.stdpath("cache") .. "/claudius.log"
local log = {}

function log.info(msg)
  local f = io.open(log_path, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [INFO] " .. msg .. "\n")
    f:close()
  end
end

function log.error(msg)
  local f = io.open(log_path, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [ERROR] " .. msg .. "\n")
    f:close()
  end
end

function log.debug(msg)
  local f = io.open(log_path, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [DEBUG] " .. msg .. "\n")
    f:close()
  end
end

-- Utility functions for JSON encoding/decoding
local function json_decode(str)
  return vim.fn.json_decode(str)
end

local function json_encode(data)
  return vim.fn.json_encode(data)
end

-- Track ongoing requests and their state
M.current_request = nil
M.request_cancelled = false

-- Folding functions
function M.get_fold_level(lnum)
  local line = vim.fn.getline(lnum)
  local last_line = vim.fn.line("$")

  -- If line starts with @, it's the start of a fold
  if line:match("^@[%w]+:") then
    return ">1"
  end

  -- If next line starts with @ or this is the last line, this is the end of the current fold
  local next_line = vim.fn.getline(lnum + 1)
  if next_line:match("^@[%w]+:") or lnum == last_line then
    return "<1"
  end

  -- Otherwise, we're inside a fold
  return "1"
end

function M.get_fold_text()
  local foldstart = vim.v.foldstart
  local line = vim.fn.getline(foldstart)
  local lines_count = vim.v.foldend - vim.v.foldstart + 1

  -- Extract the prefix (@You:, @Assistant:, etc.)
  local prefix = line:match("^(@[%w]+:)")
  if not prefix then
    return line
  end

  -- Get the first line of content (excluding the prefix)
  local content = line:sub(#prefix + 1):gsub("^%s*", "")

  -- Create fold text: prefix + first line + number of lines
  return string.format("%s %s... (%d lines)", prefix, content:sub(1, 50), lines_count)
end

-- Message types
local MSG_TYPE = {
  SYSTEM = "System",
  USER = "You",
  ASSISTANT = "Assistant",
}

-- Message selection and navigation functions
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
        prefix_end = prefix_end - 1
    }
end

local function select_in_message()
    local bounds = get_message_bounds()
    if not bounds then return end
    
    -- Get the lines
    local lines = vim.api.nvim_buf_get_lines(0, bounds.start_line - 1, bounds.inner_end, false)
    
    -- Select from after prefix to last non-empty line
    vim.api.nvim_win_set_cursor(0, {bounds.start_line, bounds.prefix_end})
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, {bounds.inner_end, #lines[#lines]})
end

local function select_message()
    local bounds = get_message_bounds()
    if not bounds then return end
    
    -- Select entire message including prefix and trailing whitespace
    vim.api.nvim_win_set_cursor(0, {bounds.start_line, 0})
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, {bounds.end_line, #vim.api.nvim_buf_get_lines(0, bounds.end_line-1, bounds.end_line, false)[1]})
end

-- Navigation functions
local function find_next_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, cur_line, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^@[%w]+:") then
      -- Get the line and find position after the colon and whitespace
      local line = vim.api.nvim_buf_get_lines(0, cur_line + i - 1, cur_line + i, false)[1]
      local col = line:find(":%s*") + 1 -- Find position after the colon
      while line:sub(col, col) == " " do -- Skip any whitespace
        col = col + 1
      end
      vim.api.nvim_win_set_cursor(0, { cur_line + i, col - 1 })
      return true
    end
  end
  return false
end

local function find_prev_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1] - 2
  if cur_line < 0 then
    return false
  end

  for i = cur_line, 0, -1 do
    local line = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1]
    if line:match("^@[%w]+:") then
      -- Get the line and find position after the colon and whitespace
      local line = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1]
      local col = line:find(":%s*") + 1 -- Find position after the colon
      while line:sub(col, col) == " " do -- Skip any whitespace
        col = col + 1
      end
      vim.api.nvim_win_set_cursor(0, { i + 1, col - 1 })
      return true
    end
  end
  return false
end

-- Module configuration
local config = {}

-- Default configuration
local default_config = {
  highlights = {
    system = "Special",
    user = "Normal",
    assistant = "Comment",
  },
  prefix_style = "bold,underline",
  ruler = {
    char = "─", -- The character to use for the ruler
    style = "NonText", -- Highlight group for the ruler
  },
  model = "claude-3-5-sonnet-20241022", -- Default Claude model to use
  keymaps = {
    normal = {
      send = "<C-]>",
      cancel = "<C-c>",
      next_message = "]m", -- Jump to next message
      prev_message = "[m", -- Jump to previous message
    },
    insert = {
      send = "<C-]>",
    },
    enable = true, -- Set to false to disable all keymaps
  },
}

-- Helper function to add rulers
local function add_rulers(bufnr)
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^@[%w]+:") then
      -- If this isn't the first line, add a ruler before it
      if i > 1 then
        -- Create virtual line with ruler
        local ruler_text = string.rep(default_config.ruler.char, math.floor(vim.api.nvim_win_get_width(0) * 1))
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, i - 1, 0, {
          virt_lines = { { { ruler_text, default_config.ruler.style } } },
          virt_lines_above = true,
        })
      end
    end
  end
end

-- Setup function to initialize the plugin
M.setup = function(opts)
  -- Merge user config with defaults
  opts = opts or {}
  config = vim.tbl_deep_extend("force", default_config, opts)

  -- Set up filetype detection for .chat files
  vim.filetype.add({
    extension = {
      chat = "chat",
    },
    pattern = {
      [".*%.chat"] = "chat",
    },
  })

  -- Define syntax highlighting and Tree-sitter configuration
  local function set_syntax()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Enable Tree-sitter for the buffer
    vim.treesitter.start(bufnr, "markdown")

    -- Define our custom syntax on top of markdown
    vim.cmd([[
      " Define the prefix matches
      syntax match ChatSystemPrefix '^@System:' contained
      syntax match ChatUserPrefix '^@You:' contained
      syntax match ChatAssistantPrefix '^@Assistant:' contained

      " Define regions that contain both prefixes and markdown
      syntax region ChatSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=ChatSystemPrefix,@Markdown
      syntax region ChatUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=ChatUserPrefix,@Markdown
      syntax region ChatAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=ChatAssistantPrefix,@Markdown
    ]])

    -- Link highlights to user config
    vim.cmd(string.format("highlight link ChatSystem %s", config.highlights.system))
    vim.cmd(string.format("highlight link ChatUser %s", config.highlights.user))
    vim.cmd(string.format("highlight link ChatAssistant %s", config.highlights.assistant))

    -- Set up prefix highlights
    vim.cmd(string.format(
      [[
      execute 'highlight ChatSystemPrefix guifg=' . synIDattr(synIDtrans(hlID("ChatSystem")), "fg", "gui") . ' gui=%s'
      execute 'highlight ChatUserPrefix guifg=' . synIDattr(synIDtrans(hlID("ChatUser")), "fg", "gui") . ' gui=%s'
      execute 'highlight ChatAssistantPrefix guifg=' . synIDattr(synIDtrans(hlID("ChatAssistant")), "fg", "gui") . ' gui=%s'
    ]],
      config.prefix_style,
      config.prefix_style,
      config.prefix_style
    ))
  end

  -- Set up folding expression
  local function setup_folding()
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = 'v:lua.require("claudius").get_fold_level(v:lnum)'
    vim.wo.foldtext = 'v:lua.require("claudius").get_fold_text()'
    -- Start with all folds open
    vim.wo.foldlevel = 99
  end

  -- Add autocmd for updating rulers
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "VimResized", "TextChanged", "TextChangedI" }, {
    pattern = "*.chat",
    callback = function(ev)
      add_rulers(ev.buf)
    end,
  })

  -- Create user commands
  vim.api.nvim_create_user_command("ClaudiusSend", function()
    M.send_to_claude()
  end, {})

  vim.api.nvim_create_user_command("ClaudiusCancel", function()
    M.cancel_request()
  end, {})

  vim.api.nvim_create_user_command("ClaudiusImport", function()
    require("claudius.import").import_buffer()
  end, {})

  vim.api.nvim_create_user_command("ClaudiusSendAndInsert", function()
    vim.cmd("stopinsert")
    M.send_to_claude({
      on_complete = function()
        vim.cmd("startinsert!")
      end,
    })
  end, {})

  -- Navigation commands
  vim.api.nvim_create_user_command("ClaudiusNextMessage", function()
    find_next_message()
  end, {})

  vim.api.nvim_create_user_command("ClaudiusPrevMessage", function()
    find_prev_message()
  end, {})

  -- Set up autocmd for the chat filetype
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    pattern = "*.chat",
    callback = function(ev)
      set_syntax()
      add_rulers(ev.buf)
    end,
  })

  -- Create the filetype detection
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "*.chat",
    callback = function()
      vim.bo.filetype = "chat"
      setup_folding()
    end,
  })

  -- Set up the mappings for Claude interaction if enabled
  if config.keymaps.enable then
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "chat",
      callback = function()
        -- Normal mode mappings
        if config.keymaps.normal.send then
          vim.keymap.set("n", config.keymaps.normal.send, function()
            M.send_to_claude()
          end, { buffer = true, desc = "Send to Claude" })
        end

        if config.keymaps.normal.cancel then
          vim.keymap.set(
            "n",
            config.keymaps.normal.cancel,
            M.cancel_request,
            { buffer = true, desc = "Cancel Claude Request" }
          )
        end

        -- Message navigation keymaps
        if config.keymaps.normal.next_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.next_message,
            find_next_message,
            { buffer = true, desc = "Jump to next message" }
          )
        end

        if config.keymaps.normal.prev_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.prev_message,
            find_prev_message,
            { buffer = true, desc = "Jump to previous message" }
          )
        end

        -- Message selection keymaps
        if config.keymaps.normal.select_in_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.select_in_message,
            select_in_message,
            { buffer = true, desc = "Select inside message content" }
          )
        end

        if config.keymaps.normal.select_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.select_message,
            select_message,
            { buffer = true, desc = "Select entire message" }
          )
        end

        -- Insert mode mapping - send and return to insert mode
        if config.keymaps.insert.send then
          vim.keymap.set("i", config.keymaps.insert.send, function()
            vim.cmd("stopinsert")
            M.send_to_claude({
              on_complete = function()
                vim.cmd("startinsert!")
              end,
            })
          end, { buffer = true, desc = "Send to Claude and continue editing" })
        end
      end,
    })
  end
end

-- Parse a single message from lines
local function parse_message(lines, start_idx)
  local line = lines[start_idx]
  local msg_type = line:match("^@([%w]+):")
  if not msg_type then
    return nil, start_idx
  end

  local content = {}
  local i = start_idx
  -- Remove the prefix from first line
  local first_content = line:sub(#msg_type + 3)
  if first_content:match("%S") then
    content[#content + 1] = first_content:gsub("^%s*", "")
  end

  i = i + 1
  -- Collect lines until we hit another prefix or end of buffer
  while i <= #lines do
    local next_line = lines[i]
    if next_line:match("^@[%w]+:") then
      break
    end
    if next_line:match("%S") or #content > 0 then
      content[#content + 1] = next_line
    end
    i = i + 1
  end

  return {
    type = msg_type,
    content = table.concat(content, "\n"),
  }, i - 1
end

-- Parse the entire buffer into a sequence of messages
function M.parse_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local messages = {}
  local i = 1

  while i <= #lines do
    local msg, last_idx = parse_message(lines, i)
    if msg then
      messages[#messages + 1] = msg
      i = last_idx + 1
    else
      i = i + 1
    end
  end

  return messages
end

-- Format messages for Claude API
local function format_messages(messages)
  local formatted = {}
  local system_message = nil

  for _, msg in ipairs(messages) do
    if msg.type == MSG_TYPE.SYSTEM then
      system_message = msg.content:gsub("%s+$", "")
    else
      local role = msg.type == MSG_TYPE.USER and "user" or msg.type == MSG_TYPE.ASSISTANT and "assistant" or nil

      if role then
        table.insert(formatted, {
          role = role,
          content = msg.content:gsub("%s+$", ""),
        })
      end
    end
  end

  return formatted, system_message
end

-- Append assistant response to buffer
local function append_response(response)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Add a newline if the last line isn't empty
  if #lines > 0 and lines[#lines]:match("%S") then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
  end

  -- Add the assistant response
  local response_lines = { "@Assistant: " .. response }
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, response_lines)
end

-- Cancel ongoing request if any
function M.cancel_request()
  if M.current_request then
    log.info("Cancelling request " .. tostring(M.current_request))

    -- Get the process ID
    local pid = vim.fn.jobpid(M.current_request)

    -- Mark as cancelled
    M.request_cancelled = true

    if pid then
      -- Send SIGINT first for clean connection termination
      vim.fn.system("kill -INT " .. pid)
      log.info("Sent SIGINT to curl process " .. pid)

      -- Give curl a moment to cleanup, then force kill if still running
      vim.defer_fn(function()
        if M.current_request then
          vim.fn.jobstop(M.current_request)
          vim.fn.system("kill -KILL " .. pid)
          log.info("Sent SIGKILL to curl process " .. pid)
          M.current_request = nil
        end
      end, 500)
    else
      -- Fallback to jobstop if we couldn't get PID
      vim.fn.jobstop(M.current_request)
      M.current_request = nil
    end

    M.current_request = nil

    -- Clean up the buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

    -- If we're still showing the thinking message, remove it
    if last_line_content:match("^@Assistant:.*Thinking%.%.%.$") then
      log.debug("Cleaning up thinking message")
      M.cleanup_spinner(bufnr)
    end

    vim.notify("Claudius: Request cancelled. See " .. log_path .. " for details.", vim.log.levels.INFO)
  else
    log.debug("Cancel request called but no current request found")
  end
end

-- Clean up spinner and prepare for response
M.cleanup_spinner = function(bufnr)
  -- Stop any existing rulers/virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Remove the "Thinking..." line
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  local prev_line = vim.api.nvim_buf_get_lines(bufnr, last_line - 2, last_line - 1, false)[1]

  -- Ensure we maintain a blank line if needed
  if prev_line and prev_line:match("%S") then
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { "" })
  else
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, {})
  end
end

-- Show loading spinner
local function start_loading_spinner()
  local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 1
  local bufnr = vim.api.nvim_get_current_buf()

  -- Clear any existing virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Check if we need to add a blank line
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines > 0 and lines[#lines]:match("%S") then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "@Assistant: Thinking..." })
  else
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant: Thinking..." })
  end

  return vim.fn.timer_start(100, function()
    if not M.current_request then
      return
    end
    frame = (frame % #spinner_frames) + 1
    local text = "@Assistant: " .. spinner_frames[frame] .. " Thinking..."
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    vim.cmd("undojoin")
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { text })
  end, { ["repeat"] = -1 })
end

-- Handle the Claude interaction
function M.send_to_claude(opts)
  opts = opts or {}
  -- Check if there's already a request in progress
  if M.current_request then
    vim.notify("Claudius: A request is already in progress. Use <C-c> to cancel it first.", vim.log.levels.WARN)
    return
  end

  log.info("Starting new Claude request")
  M.request_cancelled = false

  -- Try environment variable first
  api_key = api_key or os.getenv("ANTHROPIC_API_KEY")

  -- If no API key, prompt for it
  if not api_key then
    vim.ui.input({
      prompt = "Enter your Anthropic API key: ",
      default = "",
      border = "rounded",
      title = " Claudius - API Key Required ",
      relative = "editor",
    }, function(input)
      if input then
        api_key = input
        log.info("API key set via prompt")
        -- Continue with the Claude request immediately
        M.send_to_claude()
      else
        log.error("API key prompt cancelled")
        vim.notify("Claudius: API key required to continue", vim.log.levels.ERROR)
      end
    end)

    -- Return early since we'll continue in the callback
    return
  end

  local messages = M.parse_buffer()
  if #messages == 0 then
    vim.notify("Claudius: No messages found in buffer", vim.log.levels.WARN)
    return
  end

  local formatted_messages, system_message = format_messages(messages)
  local request_body = {
    model = config.model,
    messages = formatted_messages,
    system = system_message,
    max_tokens = 4000,
    temperature = 0.7,
    stream = true,
  }

  -- Log the outgoing request as JSON
  log.debug("Sending request to Claude API:")
  log.debug("Request body: " .. json_encode(request_body))

  local spinner_timer = start_loading_spinner()
  local response_started = false
  local function handle_response_line(line)
    -- First try parsing the line directly as JSON for error responses
    local ok, data = pcall(json_decode, line)
    if ok and data.type == "error" then
      vim.schedule(function()
        vim.fn.timer_stop(spinner_timer)
        M.cleanup_spinner(vim.api.nvim_get_current_buf())
        M.current_request = nil

        local msg = "Claude API error"
        if data.error and data.error.message then
          msg = data.error.message
        end
        vim.notify("Claudius: " .. msg .. ". See " .. log_path .. " for details.", vim.log.levels.ERROR)
      end)
      return
    end

    -- Otherwise handle normal event stream format
    if not line:match("^data: ") then
      return
    end

    local json_str = line:gsub("^data: ", "")
    if json_str == "[DONE]" then
      vim.schedule(function()
        vim.fn.timer_stop(spinner_timer)
        M.current_request = nil
      end)
      return
    end

    local ok, data = pcall(json_decode, json_str)
    if not ok then
      return
    end

    -- Handle error responses
    if data.type == "error" then
      vim.schedule(function()
        vim.fn.timer_stop(spinner_timer)
        M.cleanup_spinner(vim.api.nvim_get_current_buf())
        M.current_request = nil

        local msg = "Claude API error"
        if data.error and data.error.message then
          msg = data.error.message
        end
        vim.notify(msg .. ". See " .. log_path .. " for details.", vim.log.levels.ERROR)
      end)
      return
    end

    if data.type == "content_block_delta" and data.delta and data.delta.text then
      vim.schedule(function()
        local bufnr = vim.api.nvim_get_current_buf()

        -- Stop spinner on first content
        if not response_started then
          vim.fn.timer_stop(spinner_timer)
        end

        -- Split content into lines
        local lines = vim.split(data.delta.text, "\n", { plain = true })

        if #lines > 0 then
          local last_line = vim.api.nvim_buf_line_count(bufnr)

          if not response_started then
            -- Clean up spinner and ensure blank line
            M.cleanup_spinner(bufnr)
            last_line = vim.api.nvim_buf_line_count(bufnr)

            -- Start with @Assistant: prefix
            vim.cmd("undojoin")
            vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant: " .. lines[1] })

            -- Add remaining lines if any
            if #lines > 1 then
              vim.cmd("undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line + 1, last_line + 1, false, { unpack(lines, 2) })
            end
          else
            -- Get the last line's content
            local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

            if #lines == 1 then
              -- Just append to the last line
              vim.cmd("undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { last_line_content .. lines[1] })
            else
              -- First chunk goes to the end of the last line
              vim.cmd("undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { last_line_content .. lines[1] })

              -- Remaining lines get added as new lines
              vim.cmd("undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { unpack(lines, 2) })
            end
          end

          response_started = true
        end
      end)
    end
  end

  -- Prepare curl command with proper timeouts and signal handling
  local cmd = {
    "curl",
    "-N", -- disable buffering
    "-s", -- silent mode
    "--connect-timeout",
    "10", -- connection timeout
    "--max-time",
    "120", -- maximum time allowed
    "--retry",
    "0", -- disable retries
    "--http1.1", -- force HTTP/1.1 for better interrupt handling
    "-H",
    "Connection: close", -- request connection close
    "-H",
    "x-api-key: " .. api_key,
    "-H",
    "anthropic-version: 2023-06-01",
    "-H",
    "content-type: application/json",
    "-d",
    json_encode(request_body),
    "https://api.anthropic.com/v1/messages",
  }

  -- Start job in its own process group
  M.current_request = vim.fn.jobstart(cmd, {
    detach = true, -- Put process in its own group
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            log.debug("Received: " .. line)
            handle_response_line(line, spinner_timer)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            log.error("stderr: " .. line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      log.info("Request completed with exit code: " .. tostring(code))
      vim.schedule(function()
        M.current_request = nil
        vim.fn.timer_stop(spinner_timer)

        -- Only add the new prompt if the request wasn't cancelled and completed successfully
        if not M.request_cancelled and code == 0 and response_started then
          local bufnr = vim.api.nvim_get_current_buf()
          local last_line = vim.api.nvim_buf_line_count(bufnr)
          vim.cmd("undojoin")
          vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "", "@You: " })

          -- Move cursor to after the colon and any whitespace
          local line = vim.api.nvim_buf_get_lines(0, last_line + 1, last_line + 2, false)[1]
          local col = line:find(":%s*") + 1 -- Find position after the colon
          while line:sub(col, col) == " " do -- Skip any whitespace
            col = col + 1
          end
          vim.api.nvim_win_set_cursor(0, { last_line + 2, col - 1 })

          -- Call the completion callback if provided
          if opts.on_complete then
            opts.on_complete()
          end
        end
      end)
    end,
  })
end

return M
