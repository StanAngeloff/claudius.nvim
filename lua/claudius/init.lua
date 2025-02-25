--- Claudius plugin core functionality
--- Provides chat interface and Claude API integration
local M = {}
local ns_id = vim.api.nvim_create_namespace("claudius")
local api_key = nil
local log = {}
local current_usage = {
  input_tokens = 0,
  output_tokens = 0,
}

local session_usage = {
  input_tokens = 0,
  output_tokens = 0,
}

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
    return ">1" -- vim: foldlevel string
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
local textobject = require("claudius.textobject")

-- Navigation functions
local function find_next_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, cur_line, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^@[%w]+:") then
      -- Get the line and find position after the colon and whitespace
      local full_line = vim.api.nvim_buf_get_lines(0, cur_line + i - 1, cur_line + i, false)[1]
      local col = full_line:find(":%s*") + 1 -- Find position after the colon
      while full_line:sub(col, col) == " " do -- Skip any whitespace
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
      local full_line = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1]
      local col = full_line:find(":%s*") + 1 -- Find position after the colon
      while full_line:sub(col, col) == " " do -- Skip any whitespace
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
  signs = {
    enabled = false, -- Enable sign column highlighting (disabled by default)
    char = "▌", -- Default vertical bar character
    system = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.system
    },
    user = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.user
    },
    assistant = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.assistant
    },
  },
  notify = require("claudius.notify").default_opts,
  pricing = {
    enabled = true, -- Whether to show pricing information in notifications
  },
  model = "claude-3-7-sonnet-20250219", -- Default Claude model to use
  parameters = {
    max_tokens = 4000,    -- Maximum tokens in response
    temperature = 0.7,    -- Response creativity (0.0-1.0)
  },
  text_object = "m", -- Default text object key, set to false to disable
  editing = {
    disable_textwidth = true, -- Whether to disable textwidth in chat buffers
    auto_write = false, -- Whether to automatically write the buffer after changes
  },
  logging = {
    enabled = false, -- Logging disabled by default
    path = vim.fn.stdpath("cache") .. "/claudius.log", -- Default log path
  },
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
    enabled = true, -- Set to false to disable all keymaps
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

-- Helper function to auto-write the buffer if enabled
local function auto_write_buffer()
  if config.editing.auto_write and vim.bo.modified then
    log.debug("Auto-writing buffer")
    vim.cmd("silent! write")
  end
end

-- Setup function to initialize the plugin
M.setup = function(opts)
  -- Merge user config with defaults
  opts = opts or {}
  config = vim.tbl_deep_extend("force", default_config, opts)

  -- Setup logging
  local function write_log(level, msg)
    if config.logging and config.logging.enabled then
      local f = io.open(config.logging.path, "a")
      if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [" .. level .. "] " .. msg .. "\n")
        f:close()
      end
    end
  end

  function log.info(msg)
    write_log("INFO", msg)
  end

  function log.error(msg)
    write_log("ERROR", msg)
  end

  function log.debug(msg)
    write_log("DEBUG", msg)
  end

  -- Helper function to toggle logging
  local function toggle_logging(enable)
    if enable == nil then
      enable = not config.logging.enabled
    end
    config.logging.enabled = enable
    if enable then
      vim.notify("Claudius: Logging enabled - " .. config.logging.path)
    else
      vim.notify("Claudius: Logging disabled")
    end
  end

  -- Set up filetype detection for .chat files
  vim.filetype.add({
    extension = {
      chat = "chat",
    },
    pattern = {
      [".*%.chat"] = "chat",
    },
  })

  -- Define sign groups for each role
  if config.signs.enabled then
    -- Define signs with proper casing to match message types
    local signs = {
      ["You"] = { config = config.signs.user, highlight = config.highlights.user },
      ["System"] = { config = config.signs.system, highlight = config.highlights.system },
      ["Assistant"] = { config = config.signs.assistant, highlight = config.highlights.assistant },
    }
    -- Ensure we have lowercase versions of the role names for sign configs
    config.signs.you = config.signs.user
    for role, sign_data in pairs(signs) do
      if sign_data.config.hl ~= false then
        local sign_name = "claudius_" .. string.lower(role)
        vim.fn.sign_define(sign_name, {
          text = sign_data.config.char or config.signs.char,
          texthl = sign_data.config.hl == true and sign_data.highlight or sign_data.config.hl,
        })
      end
    end
  end

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
      -- Clear and reapply all signs
      vim.fn.sign_unplace("claudius_ns", { buffer = ev.buf })
      M.parse_buffer() -- This will reapply signs
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

  -- Logging commands
  vim.api.nvim_create_user_command("ClaudiusEnableLogging", function()
    toggle_logging(true)
  end, {})

  vim.api.nvim_create_user_command("ClaudiusDisableLogging", function()
    toggle_logging(false)
  end, {})

  vim.api.nvim_create_user_command("ClaudiusOpenLog", function()
    if not config.logging.enabled then
      vim.notify("Claudius: Logging is currently disabled", vim.log.levels.WARN)
      -- Give user time to see the warning
      vim.defer_fn(function()
        vim.cmd("tabedit " .. config.logging.path)
      end, 1000)
    else
      vim.cmd("tabedit " .. config.logging.path)
    end
  end, {})

  -- Command to recall last notification
  vim.api.nvim_create_user_command("ClaudiusRecallNotification", function()
    require("claudius.notify").recall_last()
  end, {
    desc = "Recall the last notification",
  })

  -- Set up autocmd for the chat filetype
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    pattern = { "*.chat", "chat" },
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

      -- Disable textwidth if configured
      if config.editing.disable_textwidth then
        vim.bo.textwidth = 0
      end

      -- Set autowrite if configured
      if config.editing.auto_write then
        vim.opt_local.autowrite = true
      end
    end,
  })

  -- Set up the mappings for Claude interaction if enabled
  if config.keymaps.enabled then
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

        -- Set up text objects with configured key
        textobject.setup({ text_object = config.text_object })

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

-- Place signs for a message
local function place_signs(bufnr, start_line, end_line, role)
  if not config.signs.enabled then
    return
  end

  local sign_name = "claudius_" .. string.lower(role)
  local sign_config = config.signs[string.lower(role)]
  if sign_config and sign_config.hl ~= false then
    for lnum = start_line, end_line do
      vim.fn.sign_place(0, "claudius_ns", sign_name, bufnr, { lnum = lnum })
    end
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

  local result = {
    type = msg_type,
    content = table.concat(content, "\n"),
    start_line = start_idx,
    end_line = i - 1,
  }

  -- Place signs for the message
  place_signs(vim.api.nvim_get_current_buf(), result.start_line, result.end_line, msg_type)

  return result, i - 1
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

    -- Auto-write if enabled and we've received some content
    if M.request_cancelled and not last_line_content:match("^@Assistant:.*Thinking%.%.%.$") then
      auto_write_buffer()
    end

    local msg = "Claudius: Request cancelled"
    if config.logging.enabled then
      msg = msg .. ". See " .. config.logging.path .. " for details"
    end
    vim.notify(msg, vim.log.levels.INFO)
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

  -- Auto-write the buffer before sending if enabled
  auto_write_buffer()

  -- Helper function to try getting API key from system keyring
  local function try_keyring()
    if vim.fn.has("linux") == 1 then
      local handle = io.popen("secret-tool lookup service anthropic key api 2>/dev/null")
      if handle then
        local result = handle:read("*a")
        handle:close()
        if result and #result > 0 then
          log.info("API key retrieved from system keyring")
          return result:gsub("%s+$", "") -- Trim whitespace
        end
      end
    end
    return nil
  end

  -- Try environment variable first
  api_key = api_key or os.getenv("ANTHROPIC_API_KEY")
  if api_key then
    log.info("API key found in environment variable")
  end

  -- Try system keyring if no env var
  if not api_key then
    api_key = try_keyring()
  end

  -- If still no API key, prompt for it
  if not api_key then
    log.info("No API key found in environment or keyring, prompting user")
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
    max_tokens = config.parameters.max_tokens,
    temperature = config.parameters.temperature,
    stream = true,
  }

  -- Log the outgoing request as JSON
  log.debug("Sending request to Claude API:")
  log.debug("Request body: " .. json_encode(request_body))

  local spinner_timer = start_loading_spinner()
  local response_started = false
  -- Format usage information for display with markdown
  local function format_usage(current, session)
    local pricing = require("claudius.pricing")
    local lines = {}

    -- Request usage
    if current and (current.input_tokens > 0 or current.output_tokens > 0) then
      local current_cost = config.pricing.enabled
        and pricing.calculate_cost(config.model, current.input_tokens, current.output_tokens)
      table.insert(lines, "Request:")
      if current_cost then
        table.insert(lines, string.format("  Input:  %d tokens / $%.2f", current.input_tokens or 0, current_cost.input))
        table.insert(
          lines,
          string.format(" Output:  %d tokens / $%.2f", current.output_tokens or 0, current_cost.output)
        )
        table.insert(lines, string.format("  Total:  $%.2f", current_cost.total))
      else
        table.insert(lines, string.format("  Input:  %d tokens", current.input_tokens or 0))
        table.insert(lines, string.format(" Output:  %d tokens", current.output_tokens or 0))
      end
    end

    -- Session totals
    if session and (session.input_tokens > 0 or session.output_tokens > 0) then
      local session_cost = config.pricing.enabled
        and pricing.calculate_cost(config.model, session.input_tokens, session.output_tokens)
      if #lines > 0 then
        table.insert(lines, "")
      end
      table.insert(lines, "Session:")
      if session_cost then
        table.insert(lines, string.format("  Input:  %d tokens / $%.2f", session.input_tokens or 0, session_cost.input))
        table.insert(
          lines,
          string.format(" Output:  %d tokens / $%.2f", session.output_tokens or 0, session_cost.output)
        )
        table.insert(lines, string.format("  Total:  $%.2f", session_cost.total))
      else
        table.insert(lines, string.format("  Input:  %d tokens", session.input_tokens or 0))
        table.insert(lines, string.format(" Output:  %d tokens", session.output_tokens or 0))
      end
    end
    return table.concat(lines, "\n")
  end

  local function handle_response_line(line, timer)
    -- First try parsing the line directly as JSON for error responses
    local ok, error_data = pcall(json_decode, line)
    if ok and error_data.type == "error" then
      vim.schedule(function()
        vim.fn.timer_stop(timer)
        M.cleanup_spinner(vim.api.nvim_get_current_buf())
        M.current_request = nil

        -- Auto-write on error if enabled
        auto_write_buffer()

        local msg = "Claude API error"
        if error_data.error and error_data.error.message then
          msg = error_data.error.message
        end
        local notify_msg = "Claudius: " .. msg
        if config.logging and config.logging.enabled then
          notify_msg = notify_msg .. ". See " .. config.logging.path .. " for details"
        end
        vim.notify(notify_msg, vim.log.levels.ERROR)
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
        vim.fn.timer_stop(timer)
        M.current_request = nil
      end)
      return
    end

    local parse_ok, data = pcall(json_decode, json_str)
    if not parse_ok then
      return
    end

    -- Handle error responses
    if data.type == "error" then
      vim.schedule(function()
        vim.fn.timer_stop(timer)
        M.cleanup_spinner(vim.api.nvim_get_current_buf())
        M.current_request = nil

        -- Auto-write on error if enabled
        auto_write_buffer()

        local msg = "Claude API error"
        if data.error and data.error.message then
          msg = data.error.message
        end
        local notify_msg = "Claudius: " .. msg
        if config.logging and config.logging.enabled then
          notify_msg = notify_msg .. ". See " .. config.logging.path .. " for details"
        end
        vim.notify(notify_msg, vim.log.levels.ERROR)
      end)
      return
    end

    -- Track usage information from all events
    if data.type == "message_start" then
      -- Get input tokens from message.usage in message_start event
      if data.message and data.message.usage and data.message.usage.input_tokens then
        current_usage.input_tokens = data.message.usage.input_tokens
      end
    end
    -- Track output tokens from usage field in any event
    if data.usage and data.usage.output_tokens then
      current_usage.output_tokens = data.usage.output_tokens
    end

    -- Display final usage on message_stop
    if data.type == "message_stop" and current_usage then
      vim.schedule(function()
        -- Update session totals
        session_usage.input_tokens = session_usage.input_tokens + (current_usage.input_tokens or 0)
        session_usage.output_tokens = session_usage.output_tokens + (current_usage.output_tokens or 0)

        -- Auto-write when response is complete
        auto_write_buffer()

        -- Format and display usage information using our custom notification
        local usage_str = format_usage(current_usage, session_usage)
        if usage_str ~= "" then
          local notify_opts = vim.tbl_deep_extend("force", config.notify, {
            title = "Claude Usage",
          })
          require("claudius.notify").show(usage_str, notify_opts)
        end
        -- Reset current usage for next request
        current_usage = nil
      end)
    end

    if data.type == "content_block_delta" and data.delta and data.delta.text then
      vim.schedule(function()
        local bufnr = vim.api.nvim_get_current_buf()

        -- Stop spinner on first content
        if not response_started then
          vim.fn.timer_stop(timer)
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

  -- Create temporary file for request body with claudius prefix
  local tmp_file = os.tmpname()
  -- Handle both Unix and Windows paths
  local tmp_dir = tmp_file:match("^(.+)[/\\]")
  local tmp_name = tmp_file:match("[/\\]([^/\\]+)$")
  -- Use the same separator that was in the original path
  local sep = tmp_file:match("[/\\]")
  tmp_file = tmp_dir .. sep .. "claudius_" .. tmp_name
  local f = io.open(tmp_file, "w")
  if not f then
    vim.notify("Claudius: Failed to create temporary file", vim.log.levels.ERROR)
    return
  end
  f:write(json_encode(request_body))
  f:close()

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
    "@" .. tmp_file,
    "https://api.anthropic.com/v1/messages",
  }

  -- Start job in its own process group
  -- Reset usage tracking
  current_usage = {
    input_tokens = 0,
    output_tokens = 0,
  }

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
        -- Clean up temporary file
        os.remove(tmp_file)

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

          -- Auto-write after adding the prompt if enabled
          auto_write_buffer()

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
